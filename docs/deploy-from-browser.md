# Deploying from the browser (Cloud Shell)

You do not need to install anything. Cloud Shell is a terminal built into the
Google Cloud console, with `gcloud`, `git` and `node` already set up and your
account already signed in.

## Why not pure point-and-click?

The console UI cannot run Terraform. Building ZINO by hand would mean clicking
through roughly eighteen resources — Cloud SQL, Cloud Run, the network, the
secrets, the IAM bindings — getting every setting right, and having no record of
what you did. One missed toggle is a broken deploy or an open door.

Cloud Shell is the middle ground: no local installs, still scripted, still
reproducible.

## Steps

1. Go to <https://console.cloud.google.com> and sign in.

2. Click the **terminal icon** in the top-right toolbar (`>_`). A terminal opens
   at the bottom of the page. First start takes about a minute.

3. Get the code:

   ```sh
   git clone https://github.com/ghazigh/zino
   cd zino
   git checkout claude/practical-lamport-492non
   ```

4. Install Terraform:

   ```sh
   ./scripts/install-terraform.sh
   export PATH="$HOME/bin:$PATH"
   ```

   Cloud Shell does **not** ship Terraform. What sits on `PATH` is a
   placeholder that prints install instructions and then exits *successfully* —
   so anything checking "is terraform installed?" is fooled, and `terraform
   init` appears to work while doing nothing at all. The ZINO scripts now detect
   this and refuse to continue.

   The installer puts the real binary in `~/bin`, because Cloud Shell resets
   system packages between sessions but keeps your home directory. `apt install
   terraform` would not survive a reconnect; this does.

5. Give Terraform credentials. Cloud Shell signs `gcloud` in for you, but
   Terraform reads a separate set:

   ```sh
   gcloud auth application-default login
   ```

   Follow the link it prints, approve, paste the code back.

   Two things it says that look alarming and are not:

   - *"it is not necessary to use this command"* — Cloud Shell already signs in
     `gcloud`, but Terraform reads a different credential set. Answer **y**.
   - It offers to enable `cloudresourcemanager.googleapis.com`. Answer **y**;
     it is free and only lets tools read your project list.

   > **This does not survive a Cloud Shell restart.** The credentials are
   > written under `/tmp`, which Cloud Shell clears between sessions. Your
   > cloned repo, in your home directory, does persist.
   >
   > Cloud Shell also writes them to a path Terraform does not check, so
   > Terraform would otherwise fall through to the VM's metadata server and
   > fail with `invalid token JSON from metadata`. The ZINO scripts find the
   > file and point Terraform at it, so this is handled — but if you run
   > `terraform` directly, set it yourself:
   >
   > ```sh
   > export GOOGLE_APPLICATION_CREDENTIALS="$CLOUDSDK_CONFIG/application_default_credentials.json"
   > ```

   The verification code you paste back is a one-time key to your account.
   Never paste it anywhere but that prompt.

6. Find your billing account ID:

   ```sh
   gcloud beta billing accounts list
   ```

7. Set up the project:

   ```sh
   ./scripts/bootstrap.sh --project zino-prod --billing <ID from step 6>
   ```

8. Deploy:

   ```sh
   ./scripts/deploy.sh
   ```

   It shows what it will create and waits for a yes. This is the step that
   starts costing money. When it finishes it prints your web address.

9. Open that address and register. **The first account becomes the admin.**

10. In ZINO: **Admin Panel → Settings → Connections** — add your LLM provider
    and API key. Then **Workspace → Models** to build agents.

## Notes

- **Cloud Shell disconnects after about 20 minutes idle.** Step 8 takes a while
  (Cloud SQL is slow to create). Keep the tab visible, or if it does drop,
  reconnect and re-run `./scripts/deploy.sh` — it picks up where it left off.
- **Your home directory persists** between sessions, so the cloned repo is still
  there next time.
- If a `gcloud` command errors, the script stops rather than half-applying. Send
  me the error.
