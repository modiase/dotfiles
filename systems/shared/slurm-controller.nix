{
  config,
  pkgs,
  hostName,
  heraklesAddr ? "herakles.local",
  ...
}:

let
  clusterConfig = import ./slurm-cluster.nix { inherit heraklesAddr; };
in
{
  environment.systemPackages = with pkgs; [
    slurm
  ];

  services.slurm = clusterConfig // {
    server.enable = true;
    controlMachine = hostName;
  };

  services.munge = {
    enable = true;
    password = "/var/secrets/munge.key";
  };

  system.activationScripts.setupMungeKey = ''
    mkdir -p /var/secrets
    if [ -f /Users/moye/Dotfiles/secrets/munge.key ]; then
      cp /Users/moye/Dotfiles/secrets/munge.key /var/secrets/munge.key
      chown munge:munge /var/secrets/munge.key
      chmod 0400 /var/secrets/munge.key
    fi
  '';

  system.activationScripts.setupSlurmDirs = ''
    mkdir -p /var/log/slurm
    chown slurm:slurm /var/log/slurm
  '';
}
