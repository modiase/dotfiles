{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    userName = "Moye Odiase";
    userEmail = "moyeodiase@gmail.com";
    extraConfig = {
      core.editor = "nvim";
      credential.helper = if pkgs.stdenv.isDarwin then "osxkeychain" else "${pkgs.pass-git-helper}/bin/pass-git-helper";
      filter.lfs.required = true;
      commit.verbose = true;
      rerere.enabled = true;
      gpg.format = "openpgp";
      gpg.openpgp.program = "${pkgs.gnupg}/bin/gpg";
	  push.autoSetupRemote = true;
      pull.rebase = true;
    };
  };
}
