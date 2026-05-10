# Auth Flows for Test-Driving

## Seed User Credentials

All seed users share password: `password`

### Providers

| Name | Email | Tier | Business |
|------|-------|------|----------|
| Lena Hartmann | lena.hartmann@example.com | starter | Hartmann Sport Studio |
| Markus Klein | markus.klein@example.com | starter | Klein Kreativ Werkstatt |
| Claudia Wolf | claudia.wolf@example.com | professional | Wolf Musik Akademie |
| Robert Braun | robert.braun@example.com | professional | Braun Tanz Schule |
| Katharina Richter | katharina.richter@example.com | business_plus | Richter Bildungszentrum |

### Parents

| Name | Email | Tier |
|------|-------|------|
| Anna Müller | anna.mueller@example.com | explorer |
| Thomas Schmidt | thomas.schmidt@example.com | explorer |
| Julia Hoffmann | julia.hoffmann@example.com | active |
| Stefan Schäfer | stefan.schaefer@example.com | active |

### Staff

| Name | Email | Provider |
|------|-------|----------|
| UI TestStaff | uitest-staff@example.com | Wolf Musik Akademie |

### Admin

| Name | Email |
|------|-------|
| Klass Hero Admin | app@klasshero.com |

## Login Procedure

1. Navigate to `http://localhost:4000/users/log-in`
2. Fill email field with the user's email
3. Fill password field with `password`
4. Click "Log in" button
5. Verify redirect to dashboard or intended page

## Role Selection Guide

| Testing | Use role | Recommended user |
|---------|----------|-----------------|
| Provider dashboard, sessions, programs | Provider | claudia.wolf (professional) |
| Entitlement-gated features | Provider | lena.hartmann (starter, should be denied) |
| Parent dashboard, enrollment, booking | Parent | anna.mueller |
| Admin panel, Backpex | Admin | app@klasshero.com |
| Staff dashboard, sessions, check-in/out | Staff | uitest-staff |
| Cross-role messaging | Both provider + parent in separate steps |
