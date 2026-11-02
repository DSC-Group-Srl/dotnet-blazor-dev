---
name: skill-b2c-auth
description: "Azure AD B2C JWT bearer authentication patterns for multi-tenant Blazor SaaS solutions. Use when implementing or reviewing auth configuration, token validation, or a B2C policy flow."
---

# Skill: Azure AD B2C Authentication

## Purpose

Implement the DynaHR-style auth model: Azure AD B2C with JWT Bearer tokens via `Microsoft.Identity.Web`, supporting multi-tenant SaaS sign-in and password-reset policies.

## Core Pattern

- **Server**: `Microsoft.Identity.Web` JWT Bearer validation against the B2C tenant's `AzureAdB2C` configuration section (tenant, client ID, policies such as `B2C_1_Login`, `B2C_1_ResetPassword`).
- **Client (WASM)**: MSAL-based sign-in flow, token acquisition for calling the Server API via a typed, authenticated `HttpClient`.
- **Server-to-server** (e.g. Microsoft Graph, an ERP API): a separate `AzureAD` app registration distinct from the B2C consumer-facing one — don't conflate the two.

## Multi-Tenant B2C Nuance

A B2C tenant issuing tokens for **multiple SaaS customer tenants** (not to be confused with the Azure AD B2C directory itself) commonly needs issuer validation relaxed for the B2C policy flow to work correctly across customer tenants — if a project's server disables `ValidateIssuer`, treat that as an intentional, documented decision tied to the specific B2C policy in use, not a bug to silently "fix". Confirm before changing token validation settings.

## Do Not

- Change token validation settings (issuer, audience, lifetime) without understanding the specific B2C policy configuration already in place — this is a common source of silent auth breakage across every existing tenant
- Store B2C client secrets or reset-policy details in `Client/`-side code
- Roll a custom JWT validation pipeline when `Microsoft.Identity.Web` already covers the scenario

## Reviewing for This Pattern

Flag any change to `AzureAdB2C`/`AzureAD` configuration sections or JWT Bearer options without an explicit note on *why* — auth config changes here have blast radius across every tenant, not just the one being tested.
