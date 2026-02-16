# Examples

This directory contains example code demonstrating common use cases and patterns in the Are You Ghost project.

## Available Examples

### TCP Client Example

**File:** `tcp_client_example.rs`

Demonstrates how to create a basic TCP client that connects to the game server.

**Run:**
```powershell
cargo run --example tcp_client_example
```

## Adding New Examples

To add a new example:

1. Create a new `.rs` file in this directory
2. Add documentation at the top explaining what it demonstrates
3. Update this README with the example name and description
4. Ensure the example is self-contained and runnable

## Example Code Style

Examples should:
- Be simple and focused on one concept
- Include helpful comments
- Print output to show what's happening
- Handle errors gracefully
- Be runnable with `cargo run --example <name>`
