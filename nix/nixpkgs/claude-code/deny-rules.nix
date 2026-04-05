[
  {
    rule = "Bash(gcloud secrets versions access:*)";
    reason = "Do not directly view secrets. Consider a variable or comparing hashes instead.";
    topLevelOnly = true;
  }
  {
    rule = "Bash(secrets get:*)";
    reason = "Secret access denied for security.";
  }
  {
    rule = "Bash(sed -i:*)";
    reason = "In-place file editing denied. Use the Edit tool instead.";
  }
  {
    rule = "Bash(sed -i':*)";
    reason = "In-place file editing denied. Use the Edit tool instead.";
  }
  {
    rule = "Bash(sed --in-place:*)";
    reason = "In-place file editing denied. Use the Edit tool instead.";
  }
  {
    rule = "Bash(git push:*)";
    reason = "Destructive git operation. Ask the user to run this manually.";
  }
  {
    rule = "Bash(git commit:*)";
    reason = "Use the Skill tool with /commit instead, or ask the user.";
  }
  {
    rule = "Bash(git reset --hard:*)";
    reason = "Destructive git operation. Ask the user to run this manually.";
  }
  {
    rule = "Bash(git clean:*)";
    reason = "Destructive git operation. Ask the user to run this manually.";
  }
  {
    rule = "Bash(git rebase:*)";
    reason = "Destructive git operation. Ask the user to run this manually.";
  }
  {
    rule = "Bash(git merge:*)";
    reason = "Destructive git operation. Ask the user to run this manually.";
  }
  {
    rule = "Bash(nix-collect-garbage:*)";
    reason = "Destructive nix operation denied.";
  }
  {
    rule = "Bash(nix store delete:*)";
    reason = "Destructive nix operation denied.";
  }
  {
    rule = "Bash(nix store gc:*)";
    reason = "Destructive nix operation denied.";
  }
  {
    rule = "Bash(gcloud iam:*)";
    reason = "Destructive gcloud operation denied.";
  }
  {
    rule = "Bash(gcloud storage cp:*)";
    reason = "Destructive gcloud storage operation denied.";
  }
  {
    rule = "Bash(gcloud storage mv:*)";
    reason = "Destructive gcloud storage operation denied.";
  }
  {
    rule = "Bash(gcloud storage rm:*)";
    reason = "Destructive gcloud storage operation denied.";
  }
  {
    rule = "Bash(gcloud compute instances delete:*)";
    reason = "Destructive gcloud compute operation denied.";
  }
  {
    rule = "Bash(gcloud compute instances create:*)";
    reason = "Destructive gcloud compute operation denied.";
  }
  {
    rule = "Bash(defaults write:*)";
    reason = "Writing macOS defaults is denied.";
  }
  {
    rule = "Bash(defaults delete:*)";
    reason = "Deleting macOS defaults is denied.";
  }
  {
    rule = "Bash(python3:*)";
    reason = "Turing-complete interpreter denied. Use dedicated tools or ask the user.";
  }
  {
    rule = "Bash(python:*)";
    reason = "Turing-complete interpreter denied. Use dedicated tools or ask the user.";
  }
  {
    rule = "Bash(node:*)";
    reason = "Turing-complete interpreter denied. Use dedicated tools or ask the user.";
  }
  {
    rule = "Bash(ruby:*)";
    reason = "Turing-complete interpreter denied. Use dedicated tools or ask the user.";
  }
  {
    rule = "Bash(perl:*)";
    reason = "Turing-complete interpreter denied. Use dedicated tools or ask the user.";
  }
  {
    rule = "Bash(lua:*)";
    reason = "Turing-complete interpreter denied. Use dedicated tools or ask the user.";
  }
  {
    rule = "Bash(go run:*)";
    reason = "Turing-complete interpreter denied. Use dedicated tools or ask the user.";
  }
]
