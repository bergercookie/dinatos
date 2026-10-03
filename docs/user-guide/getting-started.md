# Getting started

## Pointing the app at your instance

Dinatos is self-hosted: there's no single central server, so the app needs
to know which instance to talk to. The login screen has a **Server URL**
field (whoever runs your instance will give you this address, e.g.
`https://dinatos.example.com` or `http://192.168.1.50:8000`) -- set it there
before registering or logging in. It's saved on your device or browser, not
baked into the app, so the same app install works against any instance; you
can change it later from the settings screen too.

If your instance sits behind a self-signed certificate (common for a
homelab setup without a public CA-issued one), you may also need the
**"Allow insecure connections"**-style toggle next to the Server URL field
-- ask whoever runs your instance whether this applies to you. Leave it off
otherwise: it's a real reduction in security, only meant for a trusted
network you control.

## Creating an account

The first screen is register/login. Depending on how your instance is set
up, either:

- an account already exists for you (ask whoever runs the instance for the
  email/password), or
- you register your own from the app's Register screen -- the very first
  account ever registered on a fresh instance becomes its admin
  automatically.

## The first-run tour

The first time you sign in, Dinatos offers a short guided tour: it
dims the screen except for the one button to press next, and walks you
through choosing your units, saving a first routine, and logging a first
workout. You press the real buttons -- nothing is simulated -- and the tour
moves on as you go. **Skip step** and **Skip tour** are always on the card;
the tour is only offered once per account. To see it again, open the
profile screen and choose **Take the tour again**.

## Staying signed in

A session lasts **30 days**. There's no silent background refresh -- once a
session ends (you explicitly logged out, or 30 days passed, or whoever runs
the instance revoked it), the next request simply drops you back to the
login screen and you sign in again. Logging out from the settings screen's
app bar icon ends that session for real on the server, not just on this
device -- if you're signed in on your phone and your laptop separately,
logging out on one doesn't touch the other.
