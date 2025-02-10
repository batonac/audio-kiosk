import sys
import time
import logging
from datetime import datetime, UTC
from typing import Optional
import os

from python_mpv_jsonipc import MPV, MPVError
from peewee import *

# ---- Logging Setup ----
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ---- Database Model ----
db = SqliteDatabase(
    "kiosk.db",
    pragmas={
        "journal_mode": "wal",
        "foreign_keys": 0,
        "ignore_check_constraints": 0,
        "synchronous": 1,
    },
)


class PlaybackPosition(Model):
    playlist_url = CharField(index=True)
    item_url = CharField(index=True)
    position = IntegerField(default=0)
    updated_at = DateTimeField(default=lambda: datetime.now(UTC))

    class Meta:
        database = db
        indexes = (
            (('playlist_url', 'item_url'), True),  # Composite unique index
        )

    @staticmethod
    def get_or_create_position(playlist_url: str, item_url: str) -> tuple["PlaybackPosition", bool]:
        return PlaybackPosition.get_or_create(
            playlist_url=playlist_url,
            item_url=item_url,
            defaults={"position": 0}
        )

    @staticmethod
    def get_last_item_position(playlist_url: str) -> Optional["PlaybackPosition"]:
        return (PlaybackPosition
                .select()
                .where(PlaybackPosition.playlist_url == playlist_url)
                .order_by(PlaybackPosition.updated_at.desc())
                .first())    

    def update_position(self, new_position: int) -> None:
        self.position = new_position
        self.updated_at = datetime.now(UTC)
        self.save()


# ---- MPV Controller ----
class MPVController:
    def __init__(self, socket_path: str = f"{os.getenv('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')}/mpv.sock"):
        self.player = MPV(start_mpv=False, ipc_socket=socket_path)
        logger.info("Connected to MPV")

    def load_url(self, url: str) -> None:
        self.player.command("loadfile", url, "replace")
        time.sleep(1.0)  # Give MPV time to load

    def seek_to(self, position: int) -> None:
        if position > 0:
            self.player.command("set_property", "time-pos", position)

    def get_position(self) -> Optional[int]:
        try:
            pos = self.player.command("get_property", "time-pos")
            return int(float(pos)) if pos is not None else None
        except Exception:
            return None

    def get_current_item_url(self) -> Optional[str]:
        try:
            path = self.player.command("get_property", "path")
            return str(path) if path is not None else None
        except Exception:
            return None

    def cleanup(self) -> None:
        self.player.terminate()


# ---- Playback Handler ----
class PlaybackHandler:
    def __init__(self, mpv: MPVController):
        self.mpv = mpv
        self.current_playlist_url = None

    def play_url(self, playlist_url: str, poll_interval: float = 60.0) -> None:
        try:
            self.current_playlist_url = playlist_url
            
            # Check for last known position in this playlist
            last_position = PlaybackPosition.get_last_item_position(playlist_url)
            
            # Load playlist
            self.mpv.load_url(playlist_url)
            
            # If we have a last position, try to load that specific item and seek
            if last_position:
                self.mpv.load_url(last_position.item_url)
                self.mpv.seek_to(last_position.position)
                logger.info(f"Resuming playlist {playlist_url} at item {last_position.item_url} - {last_position.position}")
            
            # wait for the item to load
            time.sleep(10.0)

            # Poll for position updates
            logger.info("Starting position polling...")
            while True:
                pos = self.mpv.get_position()
                current_item = self.mpv.get_current_item_url()
                
                logger.info(f"Poll - Position: {pos}, Current Item: {current_item}")
                
                if pos is not None and current_item is not None:
                    position, _ = PlaybackPosition.get_or_create_position(
                        playlist_url=playlist_url,
                        item_url=current_item
                    )
                    position.update_position(pos)
                    logger.info(f"Updated position for {current_item} = {pos}")
                else:
                    logger.warning(f"Missing data - Position: {pos}, Current Item: {current_item}")
                
                time.sleep(poll_interval)

        except KeyboardInterrupt:
            raise
        except Exception as e:
            logger.error(f"Error in play_url: {e}", exc_info=True)  # Added exc_info=True


# ---- Main Application ----
def main():
    # Initialize database
    db.connect()
    db.create_tables([PlaybackPosition])

    # Initialize components
    mpv_controller = MPVController()
    playback_handler = PlaybackHandler(mpv_controller)

    try:
        # Main input loop
        for line in sys.stdin:
            url = line.strip()
            if not url:
                continue

            logger.info(f"Now playing: {url}")
            try:
                playback_handler.play_url(url)
            except KeyboardInterrupt:
                break
            except Exception as e:
                logger.error(f"Error in main loop: {e}")
                continue

    except KeyboardInterrupt:
        logger.info("Interrupted by user")
    finally:
        logger.info("Shutting down...")
        mpv_controller.cleanup()
        db.close()


if __name__ == "__main__":
    main()
