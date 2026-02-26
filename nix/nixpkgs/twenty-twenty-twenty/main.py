#!/usr/bin/env python3
import subprocess

import rumps
import objc
from Foundation import NSDistributedNotificationCenter
from AppKit import NSWorkspace, NSObject
from Quartz import (
    CGEventSourceSecondsSinceLastEventType,
    kCGAnyInputEventType,
    kCGEventSourceStateCombinedSessionState,
)
from functools import wraps

NOTIFIER = "@@TERMINAL_NOTIFIER@@"
INTERVAL = 20 * 60
IDLE_THRESHOLD = 600
TICK = 10


def requires_refresh(func):
    @wraps(func)
    def wrapper(self, *args, **kwargs):
        result = func(self, *args, **kwargs)
        self.update_title()
        return result

    return wrapper


class NotificationHandler(NSObject):
    def initWithApp_(self, app):
        self = objc.super(NotificationHandler, self).init()
        if self:
            self.app = app
        return self

    def handleSleep_(self, _):
        self.app.is_sleeping = True
        self.app.reset(None)

    def handleWake_(self, _):
        self.app.is_sleeping = False

    def handleLock_(self, _):
        self.app.is_locked = True

    def handleUnlock_(self, _):
        self.app.is_locked = False


class TwentyTwentyTwenty(rumps.App):
    def __init__(self):
        super().__init__("20-20-20")
        self.elapsed = 0
        self.active = True
        self.mute = False
        self.is_sleeping = False
        self.is_locked = False

        self.handler = NotificationHandler.alloc().initWithApp_(self)
        workspace_center = NSWorkspace.sharedWorkspace().notificationCenter()
        workspace_center.addObserver_selector_name_object_(
            self.handler, "handleSleep:", "NSWorkspaceWillSleepNotification", None
        )
        workspace_center.addObserver_selector_name_object_(
            self.handler, "handleWake:", "NSWorkspaceDidWakeNotification", None
        )

        dist_center = NSDistributedNotificationCenter.defaultCenter()
        dist_center.addObserver_selector_name_object_(
            self.handler, "handleLock:", "com.apple.screenIsLocked", None
        )
        dist_center.addObserver_selector_name_object_(
            self.handler, "handleUnlock:", "com.apple.screenIsUnlocked", None
        )

        self.menu = [
            rumps.MenuItem("Active", callback=self.toggle),
            rumps.MenuItem("Mute", callback=self.toggle_mute),
            rumps.MenuItem("Reset", callback=self.reset),
            rumps.MenuItem("Test", callback=self.test),
        ]
        self.menu["Active"].state = True
        self.menu["Mute"].state = False

    def update_title(self):
        remaining = max(0, INTERVAL - self.elapsed)
        minutes, seconds = divmod(remaining, 60)
        paused = not self.active or self.is_sleeping or self.is_locked
        self.title = f"{'⏸' if paused else ''} {minutes}:{seconds:02d}"

    @rumps.timer(TICK)
    @requires_refresh
    def tick(self, _):
        if not self.active or self.is_sleeping or self.is_locked:
            return
        idle = CGEventSourceSecondsSinceLastEventType(
            kCGEventSourceStateCombinedSessionState, kCGAnyInputEventType
        )
        if idle > IDLE_THRESHOLD:
            self.elapsed = 0
            return
        self.elapsed += TICK
        if self.elapsed >= INTERVAL:
            self.notify("Look at something 20 feet away for 20 seconds")
            self.elapsed = 0

    def notify(self, message):
        args = [NOTIFIER, "-title", "20-20-20", "-message", message]
        if not self.mute:
            args.extend(["-sound", "Tink"])
        subprocess.run(args)

    @requires_refresh
    def toggle(self, sender):
        self.active = not self.active
        sender.state = self.active
        if self.active:
            self.elapsed = 0

    def toggle_mute(self, sender):
        self.mute = not self.mute
        sender.state = self.mute

    @requires_refresh
    def reset(self, _):
        self.elapsed = 0

    @requires_refresh
    def test(self, _):
        self.elapsed = INTERVAL - 3


if __name__ == "__main__":
    TwentyTwentyTwenty().run()
