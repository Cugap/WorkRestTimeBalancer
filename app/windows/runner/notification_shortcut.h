#ifndef RUNNER_NOTIFICATION_SHORTCUT_H_
#define RUNNER_NOTIFICATION_SHORTCUT_H_

// Makes the Windows notification platform accept scheduled toasts from this
// unpackaged application: creates (or refreshes) the Start menu shortcut that
// carries the application's AppUserModelId. Without it the platform silently
// drops scheduled toasts -- immediate ones still show.
void EnsureNotificationShortcut();

#endif  // RUNNER_NOTIFICATION_SHORTCUT_H_
