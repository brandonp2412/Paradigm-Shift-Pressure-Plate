# WorkManager uses Room, whose generated *_Impl classes are instantiated
# reflectively via their no-arg constructor. R8 can't see that reflective use
# and strips the constructor, causing:
#   NoSuchMethodException: androidx.work.impl.WorkDatabase_Impl.<init> []
# at app startup (androidx.startup.InitializationProvider). Keep them.
-keep class androidx.work.** { *; }
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keepclassmembers class * extends androidx.room.RoomDatabase {
    <init>();
}

# flutter_local_notifications: keeps Gson-backed (de)serialization of scheduled
# notification details from being stripped/obfuscated.
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
