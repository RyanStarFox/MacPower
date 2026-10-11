# How to install MacPower

MacPower is a menu-bar battery monitor. It does not appear in the Dock. It requires macOS 14 or later and an Apple silicon MacBook with a battery.

## Step 1: Download and install

Open the `MacPower-*.dmg` in this folder and drag **MacPower** into **Applications**.

You can skip the disk image and run this in Terminal instead:

```bash
brew install --cask --no-quarantine ryanstarfox/tap/macpower
```

`--no-quarantine` is required. Official `homebrew/cask` does not accept this kind of package, so the command uses a personal tap. This command usually skips the block in step 2. Step 3 still applies.

## Step 2: If macOS blocks the app

The disk image is not notarized by Apple. I do not have an Apple Developer account, which costs 99 USD a year, so macOS blocks the first launch. This is not a virus. MacPower is open source. The code is in the repository, and a virus in it would be visible there.

Double-click MacPower. macOS shows the window below. Click **Done**. Do not click **Move to Trash**. Both methods start after this window.

![MacPower.app Not Opened](docs/install/gatekeeper-en.png)

Then allow it with method 1. Use method 2 if method 1 does not work.

### Method 1: Allow it in System Settings

Open **System Settings → Privacy & Security** and scroll the page to the bottom of the Security section. When you see **“MacPower.app” was blocked to protect your Mac**, click **Open Anyway** and confirm the prompt.

![Open Anyway in Privacy & Security](docs/install/privacy-en.png)

### Method 2: Clear quarantine in Terminal

Open Terminal, paste the command below, and press Enter. Nothing appears while you type the password. Press Enter when you finish:

```bash
sudo xattr -rd com.apple.quarantine /Applications/MacPower.app
```

## Step 3: Show it in the menu bar

Open **System Settings → Menu Bar**.

- Allow **MacPower** to appear in the menu bar, then launch it from Applications.
- Turning off the built-in **Battery** item is recommended, so the menu bar shows one battery icon. You can leave the system icon on.
