# Protocol overview

This document records only the interoperability details needed to understand and maintain the client.

## Architecture

The service has two main layers:

1. An HTTPS API at `https://api.smartalock.com` for account configuration, authentication, site discovery, and token refresh.
2. A WebSocket endpoint returned after site authentication for locker data and user actions.

The Flutter implementation is the authoritative executable reference in this repository.

## Authentication

The client first requests account configuration for the entered username. Depending on the response, it follows either a password flow or an OIDC/SSO flow.

Password and refresh credentials are stored through the operating system's secure storage. Session metadata required to reconnect is persisted locally by the app.

Do not log or publish passwords, bearer tokens, refresh tokens, ID tokens, UID tokens, reservation PINs, or captured private API responses.

## WebSocket session

After site authentication, the service returns controller/session information including the WebSocket endpoint. The client opens that endpoint with the issued bearer credential and performs the service authentication handshake before requesting locker data.

Requests are serialized by the client because the service response protocol is ordered rather than request-ID based.

## Data model

The client works with:

- sites;
- locker banks;
- locker sections and availability;
- current/future reservations;
- floor-plan metadata used for locker names.

Mutating actions are implemented in the application source so contributors can maintain the client. This document intentionally omits bypass-oriented instructions, captured production values, and standalone physical-access automation.

## Provenance

The source code in this repository is independently maintained client code. Decompiled application source, extracted APK resources, live credentials, and private reverse-engineering notes are not part of the repository.
