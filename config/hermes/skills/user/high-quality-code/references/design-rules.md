# Design rules

## Readability

- Descriptive names: `pendingOrders`, `calculateTotalPrice()`. Short names only when locally obvious.
- Action-oriented functions, noun-shaped types, one domain vocabulary.
- Straightforward control flow; avoid deep nesting and clever expressions.
- Separate unrelated operations; keep a logical file organization.
- A reader should grasp a component without reconstructing its whole execution path.

## Simplicity and abstraction

- Solve the actual requirement, not hypothetical extensions.
- Prefer direct code over generic machinery, inheritance and design patterns.
- No unnecessary configuration options, dependencies or files.
- Duplication becomes a defect when a business rule exists in two places.
- Justify an abstraction by clarity, consistency or maintainability, not by visual similarity alone. Three real repetitions are a stronger signal than two.
- Complexity must be paid for with a measurable benefit.

## SOLID judgment

- Single responsibility: cohesive reasons to change.
- Open/closed: extension without churn in stable code.
- Liskov: preserve behavioral contracts.
- Interface segregation: no broad interfaces for narrow callers.
- Dependency inversion: decouple high-level logic from infrastructure when it helps testing or substitution.
- Apply only where it reduces coupling or clarifies contracts. Skip interfaces, layers and injection that add ceremony without value.

## Functions

- One clear purpose, explicit inputs and outputs, few parameters.
- Validate at boundaries, minimize hidden dependencies and mutable state.
- Extract only when it improves comprehension, reuse or testability. Do not split every small operation.

## Errors and types

- No empty catch blocks, no silent ignore, no broad exception handling without justification.
- Distinguish expected failures from bugs; preserve the original context in the message.
- Do not use exceptions as ordinary control flow when a value or result type works.
- Use the language's type system: explicit contracts, accurate nullability, untrusted data validated at the boundary.
- Never cast or assert just to silence a type checker.

## Comments

- Explain why, not what. Document constraints, non-obvious business rules and public contracts.
- Remove comments that contradict the code.
- Self-documenting code first; English comments.

## Anti-patterns

God objects, spaghetti control flow, premature abstraction or optimization, unnecessary inheritance, circular dependencies, duplicated rules, magic constants, global mutable state, silent exceptions, dead code, unused imports, overly generic helpers, excessive configuration, huge unrelated refactors, inconsistent formatting.
