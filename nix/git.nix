{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    settings = {
      user.name = "Moye Odiase";
      user.email = "moyeodiase@gmail.com";
      core.editor = ''nvim --cmd "let g:pager_mode=1" -c "set nonumber norelativenumber wrap linebreak" -c "nnoremap <buffer> q :cq<CR>"'';
      core.pager = "delta";
      credential.helper =
        if pkgs.stdenv.isDarwin then "osxkeychain" else "${pkgs.pass-git-helper}/bin/pass-git-helper";
      filter.lfs.required = true;
      commit.verbose = true;
      gpg.format = "openpgp";
      gpg.openpgp.program = "${pkgs.gnupg}/bin/gpg";
      push.autoSetupRemote = true;
      pull.rebase = true;
      init.defaultBranch = "main";
      interactive.diffFilter = "delta --color-only";
      delta.navigate = true;
      delta."syntax-theme" = "gruvbox-dark";
      merge.conflictstyle = "diff3";
      diff.colorMoved = "default";
    };
    includes = [
      { path = "~/.config/git/maintenance.config"; }
    ];
  };
}
