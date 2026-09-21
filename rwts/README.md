# RWTS custom client configuration

The two `.custom.txt` files are signed RustDesk custom-client configurations. They are made and signed in the private `quicksupport-server` repository and copied here as data. The public key that verifies them is the `KEY` constant in `src/common.rs`.

- `quicksupport.custom.txt`: customer application, incoming only, settings locked.
- `technician.custom.txt`: technician application, outgoing only, server locked.

To change a setting, edit the profile in the server repository, sign it there, copy the result here, and run `rwts/check-blobs.sh`.
