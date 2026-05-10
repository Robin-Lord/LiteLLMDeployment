# SSH Backups

This is an optional side note for the server-access side of the setup. It explains how to avoid locking yourself out if a laptop dies, is lost, or is replaced.

## What must be backed up

For SSH, the critical item is the private key, not the public key.

You should back up:

- your SSH private key in encrypted form
- the SSH key passphrase
- a note of which public keys are authorized on the server
- a note of which devices hold working admin access

## Recommended setup

Prefer at least two separate admin SSH keys:

- one key for your main machine
- one key for a backup machine

Add both public keys to the server from the start if possible.

That way:

- losing one machine does not remove all admin access
- you do not need to restore from backup during an outage
- you can rotate one key without breaking the other

## Where to store backups

Reasonable options:

- your password vault, if it supports secure file attachments or secure notes
- an encrypted archive stored in a separate secure backup location

The vault should definitely hold:

- the SSH key passphrase
- a note describing where the encrypted private key backup lives

If your vault can securely store the private key backup itself, that is acceptable too.

## Practical rules

- never store an unencrypted private key in cloud storage
- do not rely on a single laptop as the only holder of admin access
- do not rely on memory for the passphrase
- do not delete old working access until new access has been tested

## Recovery model

There are three good recovery paths:

1. A second machine already has its own authorized SSH key.
2. You restore the encrypted private key backup and use the passphrase from your vault.
3. You use your cloud provider’s recovery console if you have lost normal SSH access.

The first option is the best one operationally.

## Minimal recommendation

At minimum:

- protect the SSH key with a passphrase
- store that passphrase in your password vault
- keep an encrypted backup of the private key
- have a second authorized admin key if possible
