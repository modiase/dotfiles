{
  heraklesAddr ? "herakles.local",
}:

{
  clusterName = "moye-cluster";

  nodeName = [
    "herakles NodeAddr=${heraklesAddr} CPUs=24 RealMemory=96000 Gres=gpu:1 State=UNKNOWN"
  ];

  partitionName = [
    "gpu Nodes=herakles Default=YES MaxTime=INFINITE State=UP"
  ];

  extraConfig = ''
    AccountingStorageType=accounting_storage/none
    JobAcctGatherType=jobacct_gather/none
    SlurmctldLogFile=/var/log/slurm/slurmctld.log
    SlurmdLogFile=/var/log/slurm/slurmd.log
    SelectType=select/cons_tres
    SelectTypeParameters=CR_Core_Memory
    GresTypes=gpu
  '';
}
