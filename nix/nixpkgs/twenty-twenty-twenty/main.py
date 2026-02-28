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

IDLE_THRESHOLD = 600
INTERVAL = 20 * 60
NOTIFIER = "@@TERMINAL_NOTIFIER@@"
TICK = 1


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
        self.active = True
        self.elapsed = 0
        self.is_locked = False
        self.is_sleeping = False
        self.mute = False
        self.was_idle = False

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

    @property
    def paused(self):
        return not self.active or self.is_sleeping or self.is_locked

    def update_title(self):
        if self.paused:
            self.title = "20-20-20"
            return
        remaining = max(0, INTERVAL - self.elapsed)
        minutes, seconds = divmod(remaining, 60)
        self.title = f"{minutes}:{seconds:02d}"

    @rumps.timer(TICK)
    def tick(self, _):
        if self.paused:
            return
        idle = CGEventSourceSecondsSinceLastEventType(
            kCGEventSourceStateCombinedSessionState, kCGAnyInputEventType
        )
        if idle > IDLE_THRESHOLD or self.was_idle:
            self.was_idle = idle > IDLE_THRESHOLD
            self.elapsed = 0
        elif self.elapsed >= INTERVAL:
            self.notify("Look at something 20 feet away for 20 seconds")
            self.elapsed = 0
        else:
            self.elapsed += TICK
        self.update_title()

    def notify(self, message):
        cmd = [NOTIFIER, "-title", "20-20-20", "-message", message]
        if not self.mute:
            cmd.extend(["-sound", "Tink"])
        subprocess.Popen(cmd)

    def toggle(self, sender):
        self.active = not self.active
        sender.state = self.active
        if self.active:
            self.elapsed = 0
        self.update_title()

    def toggle_mute(self, sender):
        self.mute = not self.mute
        sender.state = self.mute

    def reset(self, _):
        self.elapsed = 0
        self.update_title()

    def test(self, _):
        self.elapsed = INTERVAL - 3
        self.update_title()


if __name__ == "__main__":
    TwentyTwentyTwenty().run()
