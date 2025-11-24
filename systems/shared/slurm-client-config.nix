{ controlAddr }:

let
  clusterConfig = import ./slurm-cluster.nix { heraklesAddr = controlAddr; };
in
''
  ClusterName=${clusterConfig.clusterName}
  SlurmctldHost=herakles(${controlAddr})
  ${builtins.concatStringsSep "\n" clusterConfig.nodeName}
  ${builtins.concatStringsSep "\n" clusterConfig.partitionName}
  ${clusterConfig.extraConfig}
''
