# Devcontainer images repository instructions

## Language and writing

- Communicate in Japanese. Write `docs/` in Japanese; use English for code,
  comments, and other documentation. Use ASCII filenames.
- Add prose only for non-obvious rationale, constraints, or operational hazards.
  Update existing text rather than adding duplicate explanations.
- Plans and designs declaratively define the desired state and constraints,
  rather than migration actions or descriptions of the current state. For
  example: "sudo requires password authentication." Keep implementation steps
  and validation procedures in dedicated sections.
- README describes implemented behavior; plans describe intended behavior.

## Design references

- Consult `docs/devcontainer-implementation-plan.md` for structural changes and
  `docs/project-tools.md` for toolchains. Inventory versions are recorded project
  requirements or pins, not independently verified latest releases.
- Keep the common image generic; place project-specific toolchains in derived
  images.
- Prefer dedicated tools: rg for search, jq for JSON, yq for YAML, and ShellCheck
  for shell analysis. Report missing tools before writing replacement scripts;
  use Python when the task or project needs it.

## Container boundaries

- Use the container as the primary isolation boundary. CLI sandboxing is an
  optional additional restriction; approval checks remain enabled by default.
  Disabling CLI sandboxing must not also bypass approvals.
- Run development processes as non-root. Mount only explicitly selected
  projects, with reference repositories read-only. Do not mount the host home,
  credential directories, or Docker socket by default.
- Never include credentials or personal configuration in images or print secrets.
- Pin downloaded tools and verify published checksums when available. Agent CLIs
  follow the plan's CI image-update policy instead of fixed version pins.
- Select new application releases only after 48 hours; preserve reviewed pins
  and dependency locks on rebuilds.

## Validation

- For image changes, run `make build` when Docker is available and check affected
  tools and user permissions non-interactively. For launch changes, inspect
  commands with `make -n` and check affected mount permissions and persistence.
- Do not deploy infrastructure or access hardware merely to validate an image.
  Report checks that could not run. Documentation-only changes need prose and
  diff review, not an image rebuild.
