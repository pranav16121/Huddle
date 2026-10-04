<div align="center">

# 🏀 Huddle

**Fast, friendly, offline-first attendance tracking for basketball coaches.**

*Take roll call courtside, one-handed, in under 60 seconds.*

[![Download APK](https://img.shields.io/badge/📥_Download-huddle.apk-brightgreen?style=for-the-badge&logo=android)](https://github.com/pranav16121/Huddle/raw/main/releases/huddle.apk)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.10+-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Database](https://img.shields.io/badge/Database-SQLite-003B57?style=for-the-badge&logo=sqlite&logoColor=white)](https://www.sqlite.org/)
[![License](https://img.shields.io/badge/License-MIT-orange?style=for-the-badge)](LICENSE)

---

### 📲 [Click Here to Download `huddle.apk`](https://github.com/pranav16121/Huddle/raw/main/releases/huddle.apk)

*Install and test Huddle instantly on any Android device!*

</div>

---

## 🚀 Quick Download & Mobile Installation

Want to test Huddle on your Android phone immediately without building from source?

1. **Download the APK**: Tap the link below to download `huddle.apk` directly to your phone:
   👉 **[Download `huddle.apk` (Latest Release)](https://github.com/pranav16121/Huddle/raw/main/releases/huddle.apk)** *(or locate [`releases/huddle.apk`](releases/huddle.apk) in this repository)*.
2. **Enable Installation**: If prompted, allow your browser or file manager permission to *"Install apps from unknown sources"*.
3. **Install & Launch**: Tap the downloaded `huddle.apk` file to install and start taking attendance courtside!

---

## 🌟 Overview

**Huddle** is a specialized Flutter mobile application purpose-built for basketball coaches. Designed specifically for courtside environments, Huddle simplifies attendance logging down to quick single-hand taps while providing deep analytics into player reliability, attendance trends, and team consistency—all without requiring an internet connection.

---

## 🔥 Key Features

### ⏱️ Courtside Speed & Roll Call
- **One-Handed Roll Call**: High-contrast, tap-friendly UI designed for rapid entry while holding a clipboard or basketball.
- **Gesture Controls**:
  - **Single Tap**: Toggle **Present** / **Absent**.
  - **Long Press**: Assign **Late** or **Excused** status.
- **Bulk Actions**: *"Rest are here"* instantly marks all remaining unrecorded players present.
- **On-the-Fly Walk-Ins**: Quickly add temporary or guest players directly during an active session.
- **Instant Autosave**: Every tap is immediately saved to local storage with zero delay.

### 👥 Squad & Roster Management
- **Multiple Squads**: Effortlessly switch between Varsity, JV, Freshman, or specialized clinic rosters.
- **Smart Roster Import**: Paste a list of names to import an entire team in seconds.
- **Player Profiles & History**: Comprehensive attendance records, punctuality rates, and session logs for each player.
- **Safe Archiving**: Archive inactive players to declutter current rosters without losing historical attendance stats.

### 📈 Advanced Analytics & Insights
- **Attendance & Punctuality**: Clear percentage breakdowns for Present, Late, and Excused rates.
- **Fair Scoring Algorithm**: Excused absences never penalize a player's attendance percentage.
- **Streak Tracking**: Highlight players on active attendance streaks and identify those needing a nudge.
- **Celebratory Feedback**: Confetti animations & scoreboard styling when squad attendance hits top milestones.

### 🛡️ Bulletproof Data Safety & Privacy
- **100% Offline & Private**: All data remains exclusively on your device inside a local SQLite database (`sqflite`). No cloud required, no login needed.
- **Rolling Daily Backups**: Automated rolling backups for the last 14 days, refreshed seamlessly whenever the app transitions to the background.
- **Pre-Destructive Safety Snapshots**: Automatic snapshots created prior to deleting squads, players, or sessions (retains the last 10 snapshots).
- **Export & Import Backup Files**: Easily export a `.json` backup file to Google Drive, Email, or WhatsApp for cross-device migrations or backup storage.

---

## 🛠️ Tech Stack & Architecture

Huddle follows a modern, decoupled Flutter architecture leveraging an in-memory store backed by SQLite persistence.

```
lib/
├── main.dart                  # App bootstrap & SQLite database initialization
├── app.dart                   # Root widget, lifecycle observer & theme scoping
├── data/                      # Business Logic & Data Persistence
│   ├── models.dart            # Data entities (Player, Squad, Session, Record)
│   ├── repository.dart        # SQLite repository implementation
│   ├── store.dart             # Reactive state store & business logic
│   ├── stats.dart             # Calculation logic for streaks & attendance rates
│   ├── backup.dart            # Export/Import JSON snapshot handlers
│   └── auto_backup.dart       # Automated background backup system
└── ui/                        # Presentation Layer
    ├── theme.dart             # Custom Barlow/Barlow Condensed typography & design system
    ├── scope.dart             # InheritedWidget state dependency injection
    ├── format.dart            # Date & string formatters
    ├── screens/               # App screens (Today, Roll Call, Roster, Stats, History, Settings)
    └── widgets/               # Reusable UI components (Scoreboard, Rate Bars, Confetti)
```

### Core Libraries
- **[`sqflite`](https://pub.dev/packages/sqflite)**: Fast, reliable native SQLite local storage.
- **[`intl`](https://pub.dev/packages/intl)**: Date formatting and locale handling.
- **[`share_plus`](https://pub.dev/packages/share_plus)** & **[`file_picker`](https://pub.dev/packages/file_picker)**: Seamless backup export and restore workflows.
- **[`path_provider`](https://pub.dev/packages/path_provider)**: Platform-agnostic file directory access.

---

## 🚀 Building From Source

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`>= 3.10.3`)
- [Android Studio](https://developer.android.com/studio) / VS Code with Flutter extension
- Android Device or Emulator (API 21+)

### Installation & Run

1. **Clone the repository**:
   ```bash
   git clone https://github.com/pranav16121/Huddle.git
   cd Huddle
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run the app**:
   ```bash
   flutter run
   ```

4. **Run Unit & Widget Tests**:
   ```bash
   flutter test
   ```

---

## 📦 Building for Production

To generate a release APK:

```bash
flutter build apk --release
```

The output file will be generated at:
`build/app/outputs/flutter-apk/app-release.apk`

To install directly onto a connected device without losing existing application data:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

---

## 🤝 Contributing

Contributions, feature requests, and bug reports are welcome!
Feel free to open an issue or submit a pull request to help make Huddle even better for coaches worldwide.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AwesomeFeature`)
3. Commit your Changes (`git commit -m 'Add some AwesomeFeature'`)
4. Push to the Branch (`git checkout -b feature/AwesomeFeature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

---

<div align="center">
  Designed & Built with ❤️ for Basketball Coaches
</div>
