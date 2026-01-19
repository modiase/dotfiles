# Dotfiles & Infrastructure

## Quickstart

```bash
git clone git@github.com:modiase/Dotfiles.git ~/Dotfiles \
    && cd ~/Dotfiles \
    && bin/bootstrap \
    && source ~/.nix-profile/etc/profile.d/nix.sh \
    && bin/activate
```

## Building System Images

```bash
nix run .#build-system-image            # Interactive selection
nix run .#build-system-image -- hekate  # Build specific system
```

