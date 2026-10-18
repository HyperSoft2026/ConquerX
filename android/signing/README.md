# ConquerX Android Signing

ConquerX must use **one permanent release signing identity** for every future Android update.

## Release identity

- Alias: `conquerx-release`
- Algorithm: RSA 4096
- Validity: 10,000 days
- SHA-256 fingerprint: `7E:20:94:5D:1D:55:25:E4:D8:E6:2E:3E:AA:8A:73:BB:9E:AD:37:9E:22:50:78:94:66:36:BE:31:94:3D:3A:67`

The private keystore is intentionally **not stored in GitHub**. A public repository must never contain the release private key or its password.

## First setup

Place the private `ConquerX-release.jks` file in a private location on the release machine. Configure the Godot Android export signing fields to use:

- Keystore: the private `.jks` file
- Alias: `conquerx-release`
- Keystore password: the private password supplied with the release keystore
- Key password: the private password supplied with the release keystore

## Update rule

Every future APK/AAB release must use this exact keystore and alias. **Never generate a new release key for an update.**

If the private keystore is lost, the original signing identity cannot safely be recreated from this repository. Keep at least two encrypted backups outside GitHub.

## CI/CD

For GitHub Actions, store the keystore and password as repository/environment secrets or protected files. Never place the password, base64 keystore, or private key in source code, README files, issues, or logs.
