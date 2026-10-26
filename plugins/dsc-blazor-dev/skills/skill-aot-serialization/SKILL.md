---
name: skill-aot-serialization
description: "AOT/trim-safe JSON serialization for Blazor WASM (source-generated JsonSerializerContext, avoiding reflection). Use when a type won't serialize natively under PublishTrimmed/AOT — a tuple-keyed dictionary, a heterogeneous object bag, a complex type crossing SessionStorage/LocalStorage — before reaching for a custom JsonConverter."
---

# Skill: AOT-Safe Serialization

## Purpose

A Blazor WASM client with `RunAOTCompilation`/`PublishTrimmed` needs every serialized type resolvable
through a source-generated `JsonSerializerContext`, not reflection. Some shapes — a dictionary keyed by
a value tuple, a `Dictionary<string, object>` bag with heterogeneous values — don't serialize natively
under System.Text.Json's source generator. The instinct is to write a custom `JsonConverter<T>` for
them. That's usually the wrong first move.

## Prefer Reshaping the Data Over a Custom Converter

Before writing a `JsonConverter<T>`, check whether the *problem type* can be paired with a plain,
flat wire-shape record made only of scalar members (`string`, `int`, `decimal`, `DateOnly`, `bool`,
etc.) that System.Text.Json already knows how to handle with zero custom code:

```csharp
// ❌ First instinct: hand-roll a converter with manual Utf8JsonReader/Writer token walking —
// works, but is easy to get subtly wrong (see the STJ gotcha below) and is a maintenance burden.
public sealed class ExchangeRatesJsonConverter
    : JsonConverter<IReadOnlyDictionary<(DateOnly Date, string CurrencyCode), decimal>>
{
    public override IReadOnlyDictionary<(DateOnly, string), decimal> Read(
        ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        // manual StartArray/StartObject/property-name switch walking...
    }
    // ...
}

// ✅ Reshape instead: a flat record STJ serializes natively, no converter at all.
public sealed record ExchangeRateEntry(DateOnly Date, string CurrencyCode, decimal Rate);

public sealed class ValidationContext
{
    // The rich shape rule consumers actually want — kept for them, [JsonIgnore]'d for wire purposes.
    [JsonIgnore]
    public IReadOnlyDictionary<(DateOnly Date, string CurrencyCode), decimal> ExchangeRates { get; set; }
        = new Dictionary<(DateOnly, string), decimal>();

    // The actual wire shape — a plain List<T> of scalars, zero custom serialization code.
    [JsonInclude]
    [JsonPropertyName("ExchangeRates")]
    public List<ExchangeRateEntry> ExchangeRatesEntries
    {
        get => ExchangeRates.Select(kv => new ExchangeRateEntry(kv.Key.Date, kv.Key.CurrencyCode, kv.Value)).ToList();
        init => ExchangeRates = value.ToDictionary(e => (e.Date, e.CurrencyCode), e => e.Rate);
    }
}
```

Only reach for a real `JsonConverter<T>` when the type genuinely can't be flattened this way (rare).

## STJ Gotcha: a Second `init`-Accessor Property Poisons the Whole Type

When using the shadow-property pattern above, System.Text.Json's source generator treats **any**
second `init`-accessor property on the same type as evidence the whole type needs
parameterized-constructor-style deserialization — and then throws
(`ConstructorParameterIncompleteBinding`) because the `[JsonIgnore]`d property has no matching
"constructor parameter". Fix: the real (ignored) property must use a plain `set`, not `init` —
`init` stays only on the shadow/wire property:

```csharp
[JsonIgnore]
public Dictionary<string, object> ComputedFields { get; set; } = new();   // set, not init

[JsonInclude]
public List<ComputedFieldEntry> ComputedFieldsEntries { get; init; } = [];  // init is fine here
```

Verify any non-obvious claim about a serialization library's behavior (STJ's own edge cases included)
against actual source/docs before shipping — this exact gotcha was only caught by writing an isolated
minimal repro, not by assuming.

## Verifying AOT/Trim Safety

A passing unit test on the plain .NET test host does **not** prove AOT/trim safety by itself — it only
proves the JSON shape and converter logic are correct. The only real proof is a clean
`dotnet publish -c Release` of the Client project with no `IL2xxx`/`IL3xxx` trimmer warnings. Run it
after any change to a type that crosses `SessionStorage`/`LocalStorage` or an HTTP boundary on the
Client.

## Reviewing for This Pattern

Flag a new hand-rolled `JsonConverter<T>` that manually walks `Utf8JsonReader`/`Utf8JsonWriter` tokens
when the underlying data could instead be exposed as a flat scalar record — that's the harder-to-review,
harder-to-maintain path, not a neutral stylistic choice.
