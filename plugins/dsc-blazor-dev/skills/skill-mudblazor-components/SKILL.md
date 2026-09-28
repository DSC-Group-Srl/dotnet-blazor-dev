---
name: skill-mudblazor-components
description: "Wrapping MudBlazor (or another third-party component library) in a project-owned component library instead of consuming it directly in feature code. Use when authoring a new UI component or deciding whether to add a raw MudBlazor component to a page."
---

# Skill: Component Library Wrapping (MudBlazor pattern)

## Purpose

DynaHR wraps raw MudBlazor components in its own `DSC.Blazor.MudBlazor` library rather than using `<MudTextField>`/`<MudButton>`/etc. directly in feature pages. This skill captures when and how to do the same.

## Why Wrap

- **Single point of theming**: a brand/theme change touches the wrapper library, not every page that uses a text field
- **Consistent cross-cutting behavior**: validation-message display, loading/disabled states, and localization hookup live once, in the wrapper
- **Insulation from breaking changes**: a MudBlazor major-version upgrade is absorbed in the wrapper library, not scattered across every page

## Pattern

```csharp
// DSC.Blazor.MudBlazor/DscTextField.razor — wraps MudTextField with project defaults
<MudTextField @bind-Value="Value"
              Variant="Variant.Outlined"
              Immediate="true"
              For="@ValidationExpression"
              ...>
</MudTextField>

@code {
    [Parameter] public string? Value { get; set; }
    [Parameter] public EventCallback<string?> ValueChanged { get; set; }
    [Parameter] public Expression<Func<string?>>? ValidationExpression { get; set; }
}
```

Feature pages then consume `<DscTextField>`, not `<MudTextField>` directly.

## When to Reach for the Raw Component Instead

A one-off, page-local usage that will never need consistent cross-page theming/behavior doesn't need a wrapper — don't over-engineer a wrapper for something used in exactly one place. The threshold: if the same component configuration would otherwise be copy-pasted across 2+ pages, wrap it.

## Reviewing for This Pattern

Flag a new page that uses a raw `<Mud*>` component when the project's wrapper library already has an equivalent — that's drift from the established pattern, not a stylistic nitpick, because it reintroduces the exact per-page theming/validation duplication the wrapper exists to prevent.
