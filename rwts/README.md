# RWTS custom client configuration

The two `.custom.txt` files are signed RustDesk custom-client configurations. They are made and signed in the private `quicksupport-server` repository and copied here as data. The public key that verifies them is the `KEY` constant in `src/common.rs`.

- `quicksupport.custom.txt`: customer application, incoming only, settings locked.
- `technician.custom.txt`: technician application, outgoing only, server locked.

To change a setting, edit the profile in the server repository, sign it there, copy the result here, and run `rwts/check-blobs.sh`.

## In-app update

Both builds check `https://quicksupport.rwts.com.au/api/version/latest` on
start (`enable-check-update` is `Y` in the blobs). The response URL ends with
the release version, which is compared with `RWTS_VERSION`, a compile-time
value set from the release tag (see `build.rs`). When a newer release exists
the home page shows a card; nothing installs until the user clicks it
(`allow-auto-update` stays `N`). Files are fetched from
`/releases/<version>/` under fixed names (`rwts_update_file_name` in
`src/common.rs`). Windows portable relaunches into the new executable;
installed Windows and macOS apps update in place; a macOS app run from the
DMG is sent to the site.
