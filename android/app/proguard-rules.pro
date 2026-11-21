# google_mobile_ads pulls in WorkManager 2.7 (Room 2.2), which finds its
# database by class name (WorkDatabase_Impl) at runtime. R8 renamed it and the
# release build crashed at launch. Keep Room databases' names + constructors.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
