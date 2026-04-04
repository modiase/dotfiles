{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    signing.format = "openpgp";
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
      delta = {
        navigate = true;
        side-by-side = true;
        line-numbers = true;
        hyperlinks = true;
        file-decoration-style = "box";
        hunk-header-decoration-style = "box ul";
        syntax-theme = "ansi";
      };
      merge.conflictstyle = "zdiff3";
      diff.colorMoved = "default";
    };
    aliases = {
      wgraph = "!watch -w -t -c 'git log --graph --oneline --decorate --all --color=always'";
    };
    includes = [
      { path = "~/.config/git/maintenance.config"; }
    ];
  };
}
