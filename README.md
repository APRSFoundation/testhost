From an Administrator Command Prompt:

// Set up the environment, including the MOAI_SDK_HOME (D:\MOAI-Stuff\moai-community\scripts\..\sdk\moai-dev)
cd \moai-stuff\moai-community
scripts\env-win
// Need pito and moai on the path
path=%path%;D:\MOAI-Stuff\moai-community\bin
// Make a new project called TestHost
cd ..\projects
pito new-project TestHost
cd TestHost
// Customize the host definitions
e hostconfig.lua
  ApplicationId = "to.homeside.TestHost" --be sure to change this!
  AppName = "TestHost"
  CompanyName = "Homeside Software, Inc."

       SchemeName ="TestHost",

	   Icons = {
           hdpi = "D:/MOAI-Stuff/Projects/Try3/hosts/Try3/moai/src/main/res/drawable-hdpi/icon.png",
           mdpi = "D:/MOAI-Stuff/Projects/Try3/hosts/Try3/moai/src/main/res/drawable-mdpi/icon.png" ,
           --xdpi = "D:/MOAI-Stuff/Projects/Try3/hosts/Try3/moai/src/main/res/drawable-xdpi/icon.png" ,
           xxhdpi = "D:/MOAI-Stuff/Projects/Try3/hosts/Try3/moai/src/main/res/drawable-xxhdpi/icon.png" --leave blank to remove the default moai icon for this resolution
		}
// Create the Android and Windows hosts (Need to do this for the -s to make symbolic links)
pito host-android-studio  -c hostconfig.lua -o D:/MOAI-Stuff/Projects/TestHost//hosts/TestHost -s
pito host-windows-vs2015  -c hostconfig.lua -o D:/MOAI-Stuff/Projects/TestHost//hosts/vs2015 -s
pito host build vs2015

// Finish setting up the Android host
Fire up Android Studio
Import build.gradle (not the directory) from TestHost\hosts\TestHost directory (Remind Me Later on Android Gradle Plugin Update)
Delete ic_launcher and re-create from the Icon-Test with RMB/New/Image Asset on Res folder (Padding: -10% Shape: None)
Chnage moai's AndroidManifest.xml inside <application to:
		android:icon="@mipmap/ic_launcher"
Change moai's AndroidManifest.xml to reference @string/app_name, not a quoted string

// Add required permissions to moai's AndroidManifest.xml (before </manifest>)
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.BLUETOOTH" />
    <uses-permission android:name="android.permission.INTERNET" />

// Add multi-window to moai's AndroidManifest.xml (before <activity...)
        <meta-data android:name="com.samsung.android.sdk.multiwindow.enable" android:value="true" />
        <meta-data android:name="android.intent.category.MULTIWINDOW_LAUNCHER" android:value="true"/>
        <meta-data android:name="com.sec.android.intent.category.MULTIWINDOW_LAUNCHER" android:value="true"/>
        <!--meta-data android:name="com.samsung.android.sdk.multiwindow.style" android:value="forceTitleBar" /-->

        <meta-data android:name="com.sec.android.support.multiwindow" android:value="true"/>
        <!--meta-data android:name="com.sec.android.multiwindow.STYLE" android:value="fixedRatio"/-->
        <!--meta-data android:name="com.sec.android.multiwindow.DEFAULT_SIZE_W" android:value="640dip" /-->
        <!--meta-data android:name="com.sec.android.multiwindow.DEFAULT_SIZE_H" android:value="400dip" /-->
        <!--meta-data android:name="com.sec.android.multiwindow.MINIMUM_SIZE_W" android:value="400dip" /-->
        <!--meta-data android:name="com.sec.android.multiwindow.MINIMUM_SIZE_H" android:value="200dip" /-->

// Use app_name from values/strings.xml in moai's AndroidManifest.xml
            android:label="@string/app_name"

// Add multi-window config changes to moai's AndroidManifest.xml (attributes of <activity)
            android:launchMode="singleTask"
            android:configChanges="keyboard|keyboardHidden|orientation|screenSize|screenLayout">

// Add multi-window launcher intent to moai's AndroidManifest.xml (inside <activity's <intent-filter>)
                <category android:name="android.intent.category.MULTIWINDOW_LAUNCHER"/>

// Add service definition to moai's AndroidManifest.xml (before </application>)
        <service android:name="com.moaisdk.moai.MainService" android:exported="false" />

// Edit <project>/hosts\<Project>\settings.gradle and comment out unnecessary packages
// Edit <project>/hosts\<Project>\Moai\build.gradle and comment out unnecessary packages
// Remove extra packages from Android project

// Edit both moai and moai-core build.gradle to set targetSdkVersion to 17 and compileSdkVersion to 22
//		(This allows the real icon to be used in notifications.  To go beyond 17, we need to conditionally
//		declare a notification icon and use a largeBitmap (or some-such) in a NotificationBuilder)
		
// Set VersionName to yyyy/mm/dd hh:mm via Build / Edit Flavors... on moai

Copy actual LUA source into <Project>/src
Build/Build Project
Build/Build APK
Rename and copy to Dropbox
Download and install


