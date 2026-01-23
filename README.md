# 🏙️ City Vibes – Event Discovery & Management App

> **Final Year Project (2021–2025)**  
> **COMSATS University Islamabad, Abbottabad**  
> **Developer:** Muhammad Shahrooz (CIIT/SP22-BCS-112/ATD)

---

## 📖 Project Overview
**City Vibes** is a centralized, cross-platform mobile app that connects event organizers with attendees. It offers:

- Unified event discovery
- Secure ticket booking
- Real-time organizer analytics
- Offline ticket access

Built with **Flutter** and **Firebase**, the app follows a **modular multi-tiered architecture** for scalability, performance, and user-friendly experience.

---

## ✨ Key Features

### 👤 For Attendees
- **Event Discovery:** Browse and filter events by category, date, and location using **Google Maps API**.
- **Secure Booking:** Purchase tickets via **Stripe Payment Gateway**.
- **Offline Access:** Tickets (QR Codes) accessible offline.
- **Social Sharing:** Share events to social media.
- **Real-time Alerts:** Firebase push notifications for event updates.

### 🏢 For Organizers
- **Event Management:** Create, edit, and publish events with detailed metadata.
- **Analytics Dashboard:** Track ticket sales, revenue, and attendee engagement.
- **Wallet System:** Manage earnings and transactions.
- **Verification:** Secure organizer onboarding with identity verification (CNIC/Phone).

---

---

## 🛠️ Technology Stack
- **Frontend:** Flutter (Dart)  
- **Backend:** Firebase (Firestore, Auth, Storage, Functions)  
- **Payment:** Stripe API  
- **Location Services:** Google Maps API  
- **Architecture:** Modular Multi-tier (Presentation, Business Logic, Data Layer)  

---

## 🚀 Getting Started (Setup)

**Important:** All secret keys (Firebase, Stripe, Google Maps) are **excluded** from this repository. Use `.env` or environment variables for local development.

### 1. Prerequisites
- Flutter SDK ([Install Guide](https://docs.flutter.dev/get-started/install))  
- Android Studio or VS Code  
- Firebase Project

### 2. Clone Repository
```bash
git clone git@github.com:XenoMS-official/city-vibe-app.git
cd city-vibe-app

# instal dependencies
flutter pub get

# Add Environment Variables
STRIPE_SECRET_KEY=sk_test_XXXXXXXXXXXXXXXX
FIREBASE_API_KEY=YOUR_FIREBASE_KEY
GOOGLE_MAPS_API_KEY=YOUR_GOOGLE_MAPS_KEY


# Run the App
flutter run
