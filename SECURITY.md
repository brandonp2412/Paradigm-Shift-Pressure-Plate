# Security Policy

## Reporting a vulnerability

Please report security issues privately to the repository maintainer rather than opening a public issue when the report includes:

- authentication or session-token handling flaws;
- credentials, tokens, reservation PINs, or private site information;
- techniques that could enable unauthorized physical access;
- vulnerabilities in the upstream FloorSense or Smartalock service.

Include the affected version, reproduction conditions, and impact without attaching live credentials.

## Scope

This repository contains an unofficial client. Vulnerabilities in third-party services or the official FloorSense application should also be reported to the relevant vendor through an appropriate private disclosure channel.

## Secrets

Never commit populated `credentials.json` files, access tokens, refresh tokens, passwords, signing keys, captured private API responses, or local tool memory.
