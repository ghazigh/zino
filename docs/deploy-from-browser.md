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

4. Check Terraform is present, and install it if not:

   ```sh
   terraform version || {
     curl -fsSL -o tf.zip https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_linux_amd64.zip
     unzip -o tf.zip && mkdir -p ~/bin && mv terraform ~/bin/ && export PATH="$HOME/bin:$PATH"
     terraform version
   }
   ```

   Terraform is normally pre-installed in Cloud Shell; this covers the case
   where it is not.

5. Give Terraform credentials. Cloud Shell signs `gcloud` in for you, but
   Terraform reads a separate set:

   ```sh
   gcloud auth application-default login
   ```

   Follow the link it prints, approve, paste the code back.

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
