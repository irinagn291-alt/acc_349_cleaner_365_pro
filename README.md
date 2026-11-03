# Cleaner 365

Cleaner 365 is a free, English-language photo cleaner for iPhone. Open `Cleaner365.xcodeproj` and select the **Cleaner365** scheme. Build with Xcode 27; minimum deployment targets are iOS 18 and watchOS 11. There are no third-party dependencies. Run `xcodegen generate` after modifying `project.yml`.

## Review and cleanup

Start a 20-photo round from Today or choose a month. Swipe right to keep a photo, left to put it in the review bin. The round menu can extend the session to the rest of the month. The bin is shared by rounds and all four cleanup collections: exact duplicates, screenshots, screen recordings and videos at least 100 MB (decimal). Queued files remain in Photos until the user confirms deletion in the system dialog.

PhotoKit subtypes and the Screen Recordings smart album identify captures. The scanner narrows candidates by media type and pixel dimensions, then streams and hashes every PhotoKit resource. Resource types and bytes must match, including the motion component of Live Photos. The scan uses local data by default and offers an explicit iCloud retry for unavailable originals. Unchecked originals are never declared equal. Large videos are ordered by original resource size. Favorites are protected. Selection, the shared journal and a fresh check immediately before deletion keep at least one accessible copy of an identified set.

## Vault

Face ID unlocks an encrypted, on-device vault. Import photos or Live Photos, verify the complete copy and choose whether to remove the original. Restore to Photos creates a separate copy and keeps the vault item. The vault is excluded from backups; the key is bound to the current Face ID enrollment. Export photos before changing Face ID, moving devices or deleting the app. Private content is never sent to the widget or watch.

## Reminders, widget and watch

The bell on Today opens Reminders. The monthly reminder is off by default. Enabling it requests notification permission and schedules one passive local alert for the first day of each month at 19:00 local time, with no sound or badge. Turning it off removes the request. Tapping the reminder or the **Season progress** Home Screen widget opens the current round when available.

The small and medium widgets read aggregate review counts from the iPhone App Group. A paired Apple Watch shows the same progress and bin count, caches the last update when offline, and offers Refresh. There is no watch-side photo access or deletion. For physical devices, sign all three targets with the same team and enable `group.app.cleaner365.iphone` for the iPhone app and widget.

## Security

Open **Today → Security** to generate a password or check for exposure. Password generation uses the system random number generator. A password lookup sends the first five hexadecimal characters of its SHA-1 hash to Pwned Passwords, requests padding, and compares suffixes locally. Email lookup opens HIBP’s official account search in a browser sheet after the user submits the address.

To forward mail, open **Email aliases → Open SimpleLogin**, verify the intended mailbox in SimpleLogin, and create a personal API key. Connect the key on the iPhone, then select **Create forwarding alias**. The address and recipients shown come from SimpleLogin. The personal key stays in the device Keychain. No operator credentials or backend configuration are required.

## Testing

The scheme includes unit and UI tests. PhotoKit integration tests use a disposable simulator named **Cleaner 365 QA** with full Photos access for the app and test runner. Cleanup tests create their own byte-identical and visibly similar JPEGs, plus a valid QuickTime movie padded across the size threshold. The vault tests verify an encrypted resource cannot pass the deletion check after corruption and verify the still and motion components after restoring a Live Photo. The vault UI test requires simulated Face ID.

The optional original swipe/deletion regression requires a clean journal and exactly six purpose-made JPEGs named `qa365-0.jpg` through `qa365-5.jpg`, dated October 1–6, 2026. It checks the filenames and identifiers before exercising the system deletion dialog on the dedicated simulator.
