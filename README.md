# dmgdist

Automate the process of creating, uploading and notarizing the DMG of a Mac app.

## Building / installing

**`dmgdist` requires `create-dmg` to be installed in order to generate a DMG from the app. [Learn more about create-dmg and get the installation instructions here](https://github.com/sindresorhus/create-dmg).**

To build dmgdist, open the project in Xcode and build. You can also archive it and export the binary, then copy it to somewhere in your `$PATH`.

There's also a pre-built binary available in the project's Github releases.

## Usage

```
USAGE: dmg-dist [--verbose] [--check-request-id <check-request-id>] <app-file-path> <identity> <asc-provider> <asc-email> <asc-password>

ARGUMENTS:
  <app-file-path>         Path to the developer ID signed .app (doesn't have to be notarized) 
  <identity>              Your code signing identity, such as "Developer ID Application: John Doe (XXXX123YY)" 
  <asc-provider>          Your App Store Connect provider ID (same as your developer's team ID) 
  <asc-email>             Your App Store Connect e-mail 
  <asc-password>          Your App Store Connect app-specific password, or the identifier for a keychain item in the format
                          @keychain:ITEMNAME 

OPTIONS:
  --verbose               Verbose output 
  --check-request-id <check-request-id>
                          A notarization request id. If provided, the script will skip creating the DMG and uploading it for
                          notarization and just keep checking for the notarization status. 
  -h, --help              Show help information.
```

Example:

```
dmgdist ./My.app "Developer ID Application: JOHN DOE (123456ABCD)" "123456ABCD" "johndoe@gmail.com" "@keychain:JOHNDOEAPPSPECIFICPWD"
```

## Contributing

This tool is very simple and is designed to automate the process of creating, uploading and stapling a DMG for a Mac app. If you find any issues, feel free to open a pull request with the fix.

I don't plan on adding any additional features to it, so if it doesn't do something you need, feel free to fork and maintain your own copy.