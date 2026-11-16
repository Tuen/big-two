# WorkManager stores its jobs in Room. R8 was stripping the generated
# database and the release build died on launch (the v11 crash).
-keep class androidx.work.** { *; }
-keep class androidx.startup.** { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class androidx.work.impl.WorkDatabase { *; }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-dontwarn androidx.work.**
-dontwarn androidx.room.**
