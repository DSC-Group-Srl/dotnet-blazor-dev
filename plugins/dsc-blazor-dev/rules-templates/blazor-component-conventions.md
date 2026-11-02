# Blazor Component Conventions

## Component Library

Prefer components from the project's own wrapper library (e.g. `DSC.Blazor.MudBlazor`) over consuming a raw third-party library (MudBlazor, etc.) directly in feature code — a wrapper keeps theming and cross-cutting behavior (validation display, loading states) in one place.

## Render Modes

Be explicit about render mode per component (`InteractiveServer`, `InteractiveWebAssembly`, `InteractiveAuto`, or static SSR) rather than leaving it to a default — it determines where the component's code actually executes and what it can safely reference.

## Client-Side Safety

- `Client/` code runs in the browser. Never reference secrets, connection strings, or server-only SDKs from a `Client`-rendered component.
- Client-side HTTP calls go through typed `HttpClient` services (`Client/Services/`), not raw `HttpClient` instantiated inline in a component.
- Complex UI flow/business logic for a page belongs in a `Client/Helpers/` class, not sprawled across `@code` blocks — keeps components testable with bUnit.
- Use `Blazored.LocalStorage`/`Blazored.SessionStorage` (or the project's equivalent) for client-side state; never cache sensitive data client-side.

## Parameters & Data Binding

- `[Parameter]` properties are public, PascalCase, and should not be mutated internally — treat them as one-way input unless explicitly two-way bound (`[Parameter] EventCallback<T> ValueChanged`)
- Prefer `EventCallback<T>` over raw `Action<T>`/`Func<T>` delegates for parent-child communication — it integrates with Blazor's render lifecycle correctly

## JS Interop

- Wrap `IJSRuntime` calls in a dedicated service rather than calling `JSRuntime.InvokeAsync` directly from component code — makes it mockable in bUnit tests
- Dispose `IJSObjectReference` instances (`IAsyncDisposable`) to avoid leaking JS-side references

## Prerendering

- Guard any client-only API (`localStorage`, `IJSRuntime` calls that touch the DOM) against running during prerendering — check `RendererInfo.IsInteractive` or defer to `OnAfterRenderAsync(firstRender)`

## AOT / Trimming

If the Client project has `PublishTrimmed=true`/`RunAOTCompilation=true`:
- Avoid `Activator.CreateInstance` and other reflection-heavy patterns without explicit trimming annotations
- Prefer `System.Text.Json` source-generated serialization context over reflection-based serialization for types crossing the Client/Server boundary
- These failures only surface at `dotnet publish` time, not `dotnet build` — flag them proactively rather than waiting for a publish failure
