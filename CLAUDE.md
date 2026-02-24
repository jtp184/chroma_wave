# Agent Guide

## Project Overview
This project is a gem which binds the C code that drives Waveshare E-Paper displays, providing a simple and intuitive Ruby interface for rendering content on the display.

### Goals
- Full coverage of the Waveshare E-Paper display functionality, including all supported display models and features.
- A clean, idiomatic Ruby API that abstracts away the complexities of the underlying C code and hardware interactions.
- Efficient and legible C code that adheres to best practices for C extensions in Ruby, maximizing performance while maintaining readability and maintainability.
- Support for advanced image and color transformations out of the box, to allow users to easily manipulate images before rendering them on the display.
- Comprehensive documentation and examples to help users get started quickly and understand how to use the gem effectively.

## Guiding Principles

### Project Guidelines
- This is a greenfield project:
  - NEVER worry about "backwards compatible" changes
  - Make decisive and total refactors whenever necessary
  - Dont be afraid to throw away code that isnt used or isn't working.
- This is a hardware project:
  - Always consider the hardware implications of design and implementation decisions.
  - Use mocks and stubs to allow simulation of hardware interactions in test
  - But additionally validate designs with end-to-end tests on real hardware whenever possible.


### Orchestration and team management
- Create and use teammates as needed
- Include subject-matter expert agents to validate designs beyond just the code

### Design and Planning
- Always start with a design and plan before writing code.
- Interview the user as the product owner as needed to ensure the design is solving the right problem, and to gather requirements.
- Plans should include acceptance criteria and a clear definition of done.
- Reference specific files, classes, and methods in the design.
- Always validate designs for Correctness, Clarity, bugs & edge cases, and excellence.
- Present options / tradeoffs of stack choices to the human as part of planning
- Use the SPARC methodology when devising features
- Include visual diagrams in designs when apropriate to clarify complex interactions and structures.
- Use Emoji to deleneate sections and make designs more readable and engaging.

### Git & Github
- Use the `pull_request_template.md` template for PR descriptions. Fill out all sections.
- Commit work often to checkpoint progress and allow quick rollback. Git is free!
- Use small conventional commits, e.g.'feat: Improved workflow', 'ci: rubocop fixes', 'refactor: Simplified adapter with DRY inheritance'

### Infrastructure
- Use Github Actions for CI/CD to automate testing and deployment processes

### Software Development Best Practices
- Prefer composition over inheritance.
- Favor small classes and methods. Single Responsibility Principle.
- Depend on abstractions, not concretions.
- Write code that is easy to change. Anticipate future requirements.
- Use tests to drive design. Write tests that are easy to read and maintain.
- Refactor mercilessly. Continuously improve code quality.
- Prefer duck typing over rigid type hierarchies.
- Use dependency injection to manage dependencies.

### Ruby
- Write modern, idiomatic Ruby code. Use newer language features where appropriate.
- Use standard gems and tools, don't reinvent the wheel for common patterns with well established solutions.
- One class or module per file. File names should match class/module names. Error subclasses can be grouped with their parent.
- Use conventional mixins like `Enumerable`, `Forwardable`, and standard method names like `#succ`, `#call`, `#to_h`, etc. to integrate with other Ruby code cleanly.
- Make apropriate use of inheritance and modules to promote code reuse. DRY! 
- Use keyword argument over positional arguments whenever appropriate.
- Use `attr_accessor` and related methods to define getters and setters.
  - Use private accessors for reading internal state, never instance variables directly.
  - `#initialize` is the exception, where instance variables can be set directly.
- Metaprogramming is good, but avoid overusing it to the point where code becomes hard to understand.
  - `define_method` for `?` methods off of enumurated values is good
  - `method_missing` to dynamically handle all method calls is bad, use explicit forwarding / delegation
- Make use of `tap` and `then` to avoid temporary variables when appropriate.
- Use `when...then...` syntax with single-line case statements for conciseness
- Use Constants for regular expressions, and use `/x` mode for complex regexes
- Any given line of feature code will do one of 4 things:
  - Collecting input
    - Use keyword arguments to assert required inputs and provide defaults.
    - Prefer value objects over primitive types. Encapsulate behavior with data.
    - Provide clear interfaces for input. Use parameter builders when apropriate.
    - Use `Array()` and other conversion methods to handle flexible input types.
    - Define conversion functions where apropriate
  - Performing work
  - Delivering output
    - Handle special cases with a guard clause
  - Handling errors
    - Prefer top-level `rescue` clauses for error handling.

### RSpec, Rubocop, & RDoc
- Exercise control over the test environment with gems like `Timecop`, `FakeFS`, and `WebMock` to isolate tests from and document external dependencies.
- Test regularly to ensure correctness. Use `--fail-fast` to get feedback quickly
- Always fix all specs and linting offenses before merging. Don't merge broken code even if it seems to be preexisting.
- Follow the linter's guidance. Ignore rubocop rules only as a last resort, and always with a comment explaining why.
- If the linter rule is wrong, propose a change to the linter configuration, don't just add one-off exceptions.
- Propose custom linter rules if there are common patterns in the codebase that the default rules don't cover.
- Use RDoc to document public *and private* methods. Document parameters, return values, and any side effects or exceptions raised. Use YARD tags for complex cases.

### C Extension Code

### Basics
- C method functions **must** return `VALUE` and take `VALUE self` as first arg.
- Avoid storing `VALUE`s in C data when possible; it's error-prone.
- API naming pattern: modules `rb_mX`, classes `rb_cX`, exceptions `rb_eX`.
- Follow Ruby conventions: classes/modules `UpperCamel`, methods `snake_case`, ivars `@prefixed`, globals `$prefixed`.
- Three argument styles:
  - **Fixed args** (0–16): `VALUE meth(VALUE self, VALUE arg1, VALUE arg2)` → define with `argc = 2`
  - **C array (varargs):** `VALUE meth(int argc, VALUE* argv, VALUE self)` → define with `argc = -1`
  - **Ruby Array:** `VALUE meth(VALUE self, VALUE args)` → define with `argc = -2`
- Use `rb_scan_args(argc, argv, "21*:&", ...)` to parse optional, splat, keyword, and block args. Set defaults manually for optional args (`NIL_P(opt) ? default : opt`).
- Register with `rb_define_method(klass, "name", func, argc)`. Use `_private_method`, `_protected_method`, `_singleton_method`, `_module_function` variants as needed.
- Use `TypedData_Wrap_Struct` / `TypedData_Make_Struct` (not the legacy `Data_Wrap_Struct`).
- Always define a `rb_data_type_t` struct with:
  - `dfree`: frees your C data (or `RUBY_DEFAULT_FREE` if a plain `free()` suffices).
  - `dsize`: reports memory usage to Ruby — always implement this.
  - `dmark`: **required** if your C struct holds any `VALUE`s — call `rb_gc_mark()` on each one.
  - Set `flags = RUBY_TYPED_FREE_IMMEDIATELY` unless `dfree` releases the GVL.
- Use designated initializers (`{ .wrap_struct_name = "foo", ... }`) to zero out unused fields.
- Separate allocation (`rb_define_alloc_func`) from initialization (`initialize` method).
- Extract data with `TypedData_Get_Struct(obj, CType, &type_struct, ptr)`.
- The Ruby VM is **not thread-safe**. Never call API functions from multiple C threads simultaneously.
- All C code exposed to Ruby runs under the GVL (Global VM Lock) by default — it blocks other Ruby threads.
- For long-running C computation that doesn't use the API: release the GVL with `rb_thread_call_without_gvl(func, arg, ubf, ubf_arg)` (requires `#include <ruby/thread.h>`).
- Provide an unblocking function (`ubf`) for interruptibility, or use `RUBY_UBF_IO` for simple cases.
- To temporarily reacquire the GVL from an unlocked thread: `rb_thread_call_with_gvl(func, arg)`.

### Gotchas
- NUM2UINT and friends don't raise on negative values. All the unsigned conversion macros silently accept negatives. This is confirmed not-a-bug by Ruby core.
- NUM2CHR has two quirks: it only range-checks against int (not char), and passing a string returns the first character's numeric value instead of raising TypeError.
- Invalid names are silently created and invisible. rb_define_class(rb_cObject, "foo", ...) won't error — it just makes a class Ruby code can never access. Same for ivars without @, etc.
- Qnil is truthy in C. Only Qfalse is C-falsy (0). You must use RTEST() or NIL_P() — a bare if (value) check will treat nil as true.
- Qundef will segfault the VM if it ends up where Ruby expects a normal VALUE. It's only safe in a couple of narrow contexts (yielding nothing, unsetting constants).
- rb_eval_string runs in an isolated binding, unlike Ruby's eval. Local variables aren't shared in either direction.
- rb_rescue2 needs a trailing 0 sentinel. It's varargs — omit the 0 after your exception class list and you get undefined behavior.
- You must manually clear $! after rescuing: rb_set_errinfo(Qnil). The docs imply it's sometimes auto-cleared but in practice it never is.
- dmark isn't optional "just for safety" — if your wrapped struct holds any VALUE and you skip it, the GC will collect those objects out from under you on the next sweep. This is the single most common C extension memory bug.
- PRIsVALUE hijacks the %i specifier in rb_sprintf. So when printing an actual int, use %d — %i will be interpreted as a VALUE and likely crash.
- **Never use `rb_eval_string()`** unless there is no API equivalent. It invokes the parser, is slow, and defeats the purpose of writing C.

### Defining Classes, Modules, and Structure
- `rb_define_module("Foo")` / `rb_define_module_under(outer, "Bar")`
- `rb_define_class("Foo", rb_cObject)` / `rb_define_class_under(outer, "Bar", superclass)`
- `rb_include_module`, `rb_prepend_module`, `rb_extend_object` for mixins.
- `rb_define_const(module, "NAME", value)` for constants.
- `rb_define_attr(klass, "name", read, write)` for accessors.
