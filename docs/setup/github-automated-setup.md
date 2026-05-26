# GitHub Actions Automated Setup

> If you prefer to configure everything manually, see the [GitHub Actions Setup Guide](github-setup.md).

The `setup-github.ps1` script automates the GitHub Actions setup for ALM4Dataverse.
It mirrors the same automation available for Azure DevOps (`setup-azdo.ps1`).

The script automatically detects whether the selected repository supports GitHub
Environments **with approval rules**. It then chooses the matching setup strategy:

- **Environment mode** (when available): configures GitHub environments, required
  reviewers, and uses `promotion-mode: environment-approval` in `DEPLOY-{branch}.yml`.
- **Fallback mode** (when unavailable): configures prefixed repo-level
   secrets/variables and uses `promotion-mode: manual-gate-tag` with manual deploys from stage 1 onward.

---

## Limitations

- The account you use for setup must be in the same Entra ID tenant as the Dataverse environments.
- The process works for the standard `Azure Cloud` (`Commercial`) cloud and not `GCC` etc.
- The GitHub CLI (`gh`) must be installed before running the script.
- App Registrations created automatically will be named `{repo-name} - {env-name} - deployment`.
  You can safely rename them afterwards.
- You will be prompted to choose between two authentication types per environment:
  - **Workload Identity Federation (recommended)**: No secrets to manage or rotate.
  - **Service Principal with Secret (traditional)**: Uses a client secret that expires.
- On repository/plan combinations where environment approval rules are unavailable,
   setup automatically falls back to prefixed repo-level credentials and tag-gated
   promotion mode.

---

## Pre-requisites

Before you start, you need:

### 1) A GitHub repository

Create or use an existing GitHub repository for your Dataverse application source code.

### 2) GitHub CLI installed

Download and install the GitHub CLI from <https://cli.github.com/>.

Verify installation:

```powershell
gh --version
```

### 3) Entra ID access

You need permission to create App Registrations in the Entra ID tenant that hosts your
Dataverse environments. The setup script will create them automatically if you have that
permission, or you can provide existing App Registration details.

### 4) Application user in each Dataverse environment

For each environment, the setup script will automatically create an application user for
the selected App Registration and grant it the **System Administrator** role.

---

## Running Setup

1. Open **Windows PowerShell** from the Start menu (or PowerShell 7+).

2. Paste this in and press Enter:

   ```powershell
   iwr https://github.com/ALM4Dataverse/ALM4Dataverse/releases/latest/download/setup-github.ps1 | iex
   ```

   > If you would like to review the script first (good practice), download it from
   > <https://github.com/ALM4Dataverse/ALM4Dataverse/releases/latest/download/setup-github.ps1>

3. Follow the on-screen instructions.

---

## What Setup Does

1. **Authenticates with GitHub** — signs in via the GitHub CLI if not already logged in.
2. **Authenticates with Azure** — opens a browser to sign in to your Entra ID tenant.
3. **Selects your GitHub repository** — lists repos you have write access to.
4. **Copies workflow templates** — copies the `copy-to-your-repo/` files into your repository
   and pushes them. `DEPLOY-main.yml` is renamed to match your default branch.
5. **Configures solutions** — connects to your Dataverse DEV environment, lists unmanaged
   solutions, lets you select them in dependency order, and updates `alm-config.psd1`.
6. **Detects repository deployment capability** — checks whether GitHub environment approval
   rules are available for the selected repository.
7. **Sets up Dev credentials** — creates or reuses an Entra ID App Registration, optionally
   configures a WIF federated credential, and then:
   - stores credentials in a GitHub environment (`Dev-{branch}`) **when environment mode is available**, or
   - stores credentials as prefixed repo-level secrets/variables (for example `DEV_MAIN_*`) **in fallback mode**.
8. **Sets up deployment environment credentials** — repeats step 7 for each deployment
   environment you add (TEST-main, PROD, UAT, etc.), including environment approvals when supported.
9. **Generates deployment promotion mode automatically** — writes `DEPLOY-{branch}.yml`
   with `promotion-mode: environment-approval` in environment mode, otherwise
   `promotion-mode: manual-gate-tag` (manual trigger required for every stage).
   Generated `environment-approval` DEPLOY workflows also allow `target-environment`
   to be left blank for manual replays, which starts from the first configured stage.
   In `manual-gate-tag` mode, `target-environment` remains mandatory.
10. **Applies workflow timeout defaults** — configures workflow calls to pass
    `timeout-minutes: 360` (matching Azure DevOps template defaults) for BUILD,
    EXPORT, IMPORT, and each DEPLOY stage.

---

## Post-Setup Steps

After the script completes:

1. Go to **Actions** in your repository — the `BUILD`, `EXPORT`, `IMPORT`, and `DEPLOY-main`
   workflows are ready.
2. Review the selected credential storage location:
   - **Environment mode**: credentials are in **Settings** > **Environments** > `{EnvironmentName}`
   - **Fallback mode**: credentials are in **Settings** > **Secrets and variables** > **Actions**
     with environment-derived prefixes (for example `DEV_MAIN_*`, `TEST_*`, `PROD_*`).
3. If environment mode was selected, verify required reviewers on each environment in
   **Settings** > **Environments**.
4. Review `DEPLOY-{branch}.yml` and confirm the generated `promotion-mode`:
   - `environment-approval` when environment approvals are available
   - `manual-gate-tag` when fallback mode is used
   (every deployment stage is triggered manually; later stages also require the previous stage's success tag)
   See [Deployment Gates for GitHub Free](github-setup.md#deployment-gates-for-github-free)
   and [GitHub licence limitations](github-setup.md#github-licence-limitations) for details.

---

## Adding Environments Later

Re-run the script at any time to add more deployment environments. Previously entered
credentials are offered as re-use options to avoid re-entering them.

---

## See Also

- [GitHub Actions Setup Guide](github-setup.md) — full manual setup instructions
- [GitHub Secrets & Variables Reference](../config/github-secrets.md)
