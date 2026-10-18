# Bugsee


Bugsee is a mobile SDK that adds crucial information to your bug and crash reports. Bugsee reports include video of user actions, network traffic, console logs and many other important traces from your app. Now you know what exactly led to the unexpected behavior.

Sign up for a service at [https://www.bugsee.com](https://www.bugsee.com). 

## Installation

Bugsee requires **iOS 15.0** or later (tvOS 15.0, visionOS 1.0).

**Swift Package Manager**

Navigate to the SPM section in your project, add a new package, point it to

```bash
https://github.com/bugsee/spm
```
and select the latest version. While 7.x is in beta, set the dependency rule to
**Exact Version**: Swift Package Manager keeps pre-release versions out of version
ranges, so "Up to Next Major Version" will not resolve a beta.

**Direct download**

For integrations that cannot resolve a Swift package — Unity projects, or any
build that embeds frameworks by hand — download and embed the XCFramework. This is
the same archive the Swift package resolves:

```bash
https://download.bugsee.com/sdk/ios/spm/Bugsee-<version>.zip
```

The archive also contains a `Tools/` folder with the `BugseeAgent` and `BugseeClean`
symbol-upload scripts. Keep it inside the folder that contains your `.xcodeproj`,
where the [dSYM upload script](https://docs.bugsee.com/sdk/ios/symbolication/)
looks for `BugseeAgent`.

CocoaPods and Carthage are no longer supported. Projects still on either one
should migrate to Swift Package Manager or to the direct download above.

Upgrading from 6.x? Many APIs and every option key changed in 7.x. See the
[migration guide](https://docs.bugsee.com/sdk/ios/v7/migration/).

**In-app feedback**

The feedback/chat feature ships as a separate package,
[`BugseeFeedback`](https://github.com/bugsee/feedback-spm). Add it at the same exact
version as `Bugsee` only if your app uses in-app feedback.

**Import**

Import Bugsee header file in your app delegate or the file you intend to initialize the framework from

**Objective-C**
```objective-c
@import Bugsee;
```

**Swift**
```swift
import Bugsee
```

**SwiftUI**

When installed via Swift Package Manager, Bugsee also ships an optional `BugseeSwiftUI`
module with SwiftUI conveniences (such as protecting sensitive views from recordings).
Import it alongside `Bugsee` where you use those helpers:

```swift
import Bugsee
import BugseeSwiftUI

// Hide a sensitive view from video recordings:
Text(secret)
    .bugseeProtect()
```

`BugseeSwiftUI` requires iOS 15+, same as the core `Bugsee` module.

## Initialization

Locate your app delegate and initialize the framework in your *application:didFinishLaunchingWithOptions* method:

**Objective-C**
```objective-c
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // ...other initialization code

    [Bugsee launchWithToken:@"your_app_token"];

    return YES;
}
```

**Swift**
```swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // ...other initialization code

    Bugsee.launch(token:"your_app_token")

    return true
}
```

## Configuration

### Launching with options

Bugsee behavior is very customizable, if default configuration is not satisfying your needs you can launch the SDK with additional parameters passed as a dictionary.

**Objective-C**
```objective-c
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // ...other initialization code

    NSDictionary * options = @{
           BugseeOptionConfigDuration               : @60,
           BugseeOptionReportingTriggerByShake      : BugseeTrue,
           BugseeOptionReportingTriggerByScreenshot : BugseeTrue,
           BugseeOptionDetectAndReportCrash         : BugseeTrue
    };

    [Bugsee launchWithToken:@"your_app_token" andOptions:options];

    return YES;
}
```

**Swift**
```swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // ...other initialization code

    let options : [String: Any] =
        [ BugseeOptionConfigDuration               : 60,
          BugseeOptionReportingTriggerByShake      : false,
          BugseeOptionReportingTriggerByScreenshot : true,
          BugseeOptionDetectAndReportCrash         : true ]

    Bugsee.launch(token: "your_app_token", dictionaryOptions: options)

    return true
}
```

### Available Options
|Key|Default value|Notes
|---|---|---|
|BugseeOptionConfigDuration|@60|Maximum recording duration, in seconds|
|BugseeOptionReportingTriggerByShake|YES|Shake gesture to trigger report|
|BugseeOptionReportingTriggerByScreenshot|NO|Screenshot to trigger report|
|BugseeOptionDetectAndReportCrash|YES|Catch and report application crashes (\*)|

\* iOS allows only one crash detector to be active at a time, if you insist on using an alternative solution for handling crashes, you might want to use this option and disable Bugsee from taking over.

Always pass the `BugseeOption*` constants: a key typed out as a plain string is ignored
without any warning. The full list of keys is in the
[migration guide](https://docs.bugsee.com/sdk/ios/v7/migration/#2-option-keys).

### Setting the user identifier

When you already have your users identified within your app, you might want to attach their identifier (an email address, for example) to every report automatically. Bugsee provides APIs for setting, getting and clearing it.

**Objective-C**
```objective-c
    // setting the identifier
    [Bugsee setUserIdentifier:@"name@example.com"];

    // getting the identifier, nil will be returned if it was never set
    NSString *identifier = [Bugsee getUserIdentifier];

    // clearing the identifier
    [Bugsee clearUserIdentifier];
```

**Swift**
```swift
    // setting the identifier
    Bugsee.setUserIdentifier("name@example.com")

    // getting the identifier, nil will be returned if it was never set
    let identifier = Bugsee.getUserIdentifier()

    // clearing the identifier
    Bugsee.clearUserIdentifier()
```
## Manual invocation

### Report view

In addition to detection of shake gesture or screenshot issue report view can be triggered programmatically:

**Objective-C**
```objective-c
[Bugsee showReportDialog];

// or pre-fill some fields, user will be able to modify them
[Bugsee showReportDialogWithSummary:@"Some problem"
          description:@""
          severity:BugseeSeverityMedium];
```

**Swift**
```swift
Bugsee.showReportDialog()

// or pre-fill some fields, user will be able to modify them
Bugsee.showReportDialog(summary: "Some problem",
    description: "",
    severity: BugseeSeverityMedium)
```

### Issue create

You can build your own custom UI for collecting summary, description and severity from a user and use the following call to send it to Bugsee
to upload.
Note: You should not use it for reporting errors automatically from within code, use [Non-fatal errors](#non-fatal-errors) for this instead.

**Objective-C**
```objective-c
[Bugsee uploadWithSummary:@"Upload from code"
        description:@"Some description"
        severity:BugseeSeverityMedium];
```

**Swift**
```swift
Bugsee.upload(summary: "Upload from code",
        description: "Some description",
        severity: BugseeSeverityMedium)
```

### Non-fatal errors

It is possible to report non-fatal errors from code. These reports will get combined similar to crashes,
and you will be provided with statistics and a break down by unique devices, iOS versions, etc.

**Objective-C**
```objective-c
[Bugsee logError:[NSError errorWithDomain:@"com.example.errors.ServerIsDown"
							code:10234 userInfo:@{
								@"key1":@"value1",
								@"key2": @"value2"}]];
```

**Swift**
```swift
Bugsee.logError(error: NSError(domain: "com.example.errors.ServerIsDown",
						code: 10234,
						userInfo: ["key1": "value1", "key2": "value2"]))
```


## User events

User events can be attached to the report, events are identified by a string and can have an optional dictionary of parameters that will be stored and passed along with the report.

**Objective-C**
```objective-c
    // Without any additional parameters
    [Bugsee event:@"payment_processed"];

    // ...or with additional custom parameters
    [Bugsee event:@"payment_processed"
           params:@{
               @"amount": @125,
               @"currency": @"USD"
           }];
```

**Swift**
```swift
    // Without any additional parameters
    Bugsee.event("payment_processed")

    // ...or with additional custom parameters
    Bugsee.event("payment_processed",
      params:["amount": 125, "currency": "USD"])
```

## User traces

User traces can be attached to the report, this may be useful when you want to trace how a specific variable or state changes over time right before the problem happens.

Set the trace's value every time it changes.

**Objective-C**
```objective-c
    // Set value of @15 to the trace named "credit_balance"
    // any time it changes
    [Bugsee trace:@"credit_balance" value:@15];
```

**Swift**
```swift
    // Set value of 15 to the trace named "credit_balance"
    // any time it changes
    Bugsee.trace("credit_balance", value: 15)
```


Bugsee can be further customized and allows adding your own traces, events, logs etc., for a complete SDK documentation covering additional options and API's visit [https://docs.bugsee.com/](https://docs.bugsee.com/)
