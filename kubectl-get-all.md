NAMESPACE        NAME                                                 READY   STATUS    RESTARTS   AGE
ecommerce-demo   pod/service-orders-654b4c9db-vx7vd                   1/1     Running   0          61m
ecommerce-demo   pod/service-payments-85d48885bc-42kqn                1/1     Running   0          52m
kube-system      pod/azure-cns-q9t9c                                  2/2     Running   0          162m
kube-system      pod/azure-ip-masq-agent-5rz4f                        1/1     Running   0          162m
kube-system      pod/cloud-node-manager-wb966                         1/1     Running   0          162m
kube-system      pod/coredns-7d4699998d-2bph6                         1/1     Running   0          161m
kube-system      pod/coredns-7d4699998d-n7562                         1/1     Running   0          163m
kube-system      pod/coredns-autoscaler-bcc8bd9f-kktqn                1/1     Running   0          163m
kube-system      pod/csi-azuredisk-node-xzn7q                         3/3     Running   0          162m
kube-system      pod/csi-azurefile-node-x6gvm                         4/4     Running   0          162m
kube-system      pod/konnectivity-agent-79778b6996-m89lc              1/1     Running   0          141m
kube-system      pod/konnectivity-agent-79778b6996-thhgd              1/1     Running   0          141m
kube-system      pod/konnectivity-agent-autoscaler-6f75c49d4f-jfp9x   1/1     Running   0          163m
kube-system      pod/kube-proxy-xl6s5                                 1/1     Running   0          162m
kube-system      pod/metrics-server-c7f8fcc7c-dfbn9                   2/2     Running   0          161m
kube-system      pod/metrics-server-c7f8fcc7c-zm5xs                   2/2     Running   0          161m
kubecost         pod/kubecost-aggregator-0                            1/1     Running   0          29m
kubecost         pod/kubecost-cloud-cost-796df7785c-ssphv             1/1     Running   0          29m
kubecost         pod/kubecost-cluster-controller-67d98848d6-d8wjr     1/1     Running   0          92m
kubecost         pod/kubecost-finopsagent-5bc444c67b-b8kww            1/1     Running   0          79m
kubecost         pod/kubecost-forecasting-64f5494c4f-vcwnd            1/1     Running   0          29m
kubecost         pod/kubecost-frontend-7bc698865b-7vbtx               1/1     Running   0          92m
kubecost         pod/kubecost-local-store-59bbfbf855-j2hbc            1/1     Running   0          92m
kubecost         pod/kubecost-mcp-5d4b95887f-r54lf                    1/1     Running   0          92m
kubecost         pod/kubecost-network-costs-qmtks                     1/1     Running   0          92m

NAMESPACE        NAME                                          TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)             AGE
default          service/kubernetes                            ClusterIP   10.0.0.1       <none>        443/TCP             164m
ecommerce-demo   service/service-orders                        ClusterIP   10.0.218.193   <none>        80/TCP              61m
ecommerce-demo   service/service-payments                      ClusterIP   10.0.17.111    <none>        80/TCP              61m
kube-system      service/kube-dns                              ClusterIP   10.0.0.10      <none>        53/UDP,53/TCP       164m
kube-system      service/metrics-server                        ClusterIP   10.0.222.14    <none>        443/TCP             163m
kubecost         service/kubecost-aggregator                   ClusterIP   10.0.209.208   <none>        9004/TCP,9363/TCP   92m
kubecost         service/kubecost-cloud-cost                   ClusterIP   10.0.85.223    <none>        9005/TCP            92m
kubecost         service/kubecost-cluster-controller-service   ClusterIP   10.0.188.30    <none>        9732/TCP            92m
kubecost         service/kubecost-finopsagent                  ClusterIP   10.0.32.117    <none>        80/TCP              92m
kubecost         service/kubecost-forecasting                  ClusterIP   10.0.100.157   <none>        5000/TCP            92m
kubecost         service/kubecost-frontend                     ClusterIP   10.0.128.80    <none>        9090/TCP            92m
kubecost         service/kubecost-local-store                  ClusterIP   10.0.176.184   <none>        9006/TCP            92m
kubecost         service/kubecost-mcp                          ClusterIP   10.0.149.63    <none>        3030/TCP            92m
kubecost         service/kubecost-network-costs                ClusterIP   None           <none>        3001/TCP            92m

NAMESPACE     NAME                                            DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
kube-system   daemonset.apps/azure-cns                        1         1         1       1            1           <none>          164m
kube-system   daemonset.apps/azure-cns-win                    0         0         0       0            0           <none>          164m
kube-system   daemonset.apps/azure-ip-masq-agent              1         1         1       1            1           <none>          164m
kube-system   daemonset.apps/cloud-node-manager               1         1         1       1            1           <none>          163m
kube-system   daemonset.apps/cloud-node-manager-windows       0         0         0       0            0           <none>          163m
kube-system   daemonset.apps/csi-azuredisk-node               1         1         1       1            1           <none>          163m
kube-system   daemonset.apps/csi-azuredisk-node-win           0         0         0       0            0           <none>          163m
kube-system   daemonset.apps/csi-azurefile-node               1         1         1       1            1           <none>          163m
kube-system   daemonset.apps/csi-azurefile-node-win           0         0         0       0            0           <none>          163m
kube-system   daemonset.apps/kube-proxy                       1         1         1       1            1           <none>          163m
kube-system   daemonset.apps/windows-kube-proxy-initializer   0         0         0       0            0           <none>          163m
kubecost      daemonset.apps/kubecost-network-costs           1         1         1       1            1           <none>          92m

NAMESPACE        NAME                                            READY   UP-TO-DATE   AVAILABLE   AGE
ecommerce-demo   deployment.apps/service-orders                  1/1     1            1           61m
ecommerce-demo   deployment.apps/service-payments                1/1     1            1           61m
kube-system      deployment.apps/coredns                         2/2     2            2           164m
kube-system      deployment.apps/coredns-autoscaler              1/1     1            1           164m
kube-system      deployment.apps/konnectivity-agent              2/2     2            2           163m
kube-system      deployment.apps/konnectivity-agent-autoscaler   1/1     1            1           163m
kube-system      deployment.apps/metrics-server                  2/2     2            2           163m
kubecost         deployment.apps/kubecost-cloud-cost             1/1     1            1           92m
kubecost         deployment.apps/kubecost-cluster-controller     1/1     1            1           92m
kubecost         deployment.apps/kubecost-finopsagent            1/1     1            1           92m
kubecost         deployment.apps/kubecost-forecasting            1/1     1            1           92m
kubecost         deployment.apps/kubecost-frontend               1/1     1            1           92m
kubecost         deployment.apps/kubecost-local-store            1/1     1            1           92m
kubecost         deployment.apps/kubecost-mcp                    1/1     1            1           92m

NAMESPACE        NAME                                                       DESIRED   CURRENT   READY   AGE
ecommerce-demo   replicaset.apps/service-orders-654b4c9db                   1         1         1       61m
ecommerce-demo   replicaset.apps/service-payments-649fc44965                0         0         0       61m
ecommerce-demo   replicaset.apps/service-payments-7b944b874d                0         0         0       52m
ecommerce-demo   replicaset.apps/service-payments-85d48885bc                1         1         1       52m
kube-system      replicaset.apps/coredns-7d4699998d                         2         2         2       163m
kube-system      replicaset.apps/coredns-autoscaler-bcc8bd9f                1         1         1       163m
kube-system      replicaset.apps/konnectivity-agent-79778b6996              2         2         2       141m
kube-system      replicaset.apps/konnectivity-agent-7b55fc9bc9              0         0         0       163m
kube-system      replicaset.apps/konnectivity-agent-autoscaler-6f75c49d4f   1         1         1       163m
kube-system      replicaset.apps/metrics-server-6769b5cc57                  0         0         0       163m
kube-system      replicaset.apps/metrics-server-c7f8fcc7c                   2         2         2       161m
kubecost         replicaset.apps/kubecost-cloud-cost-796df7785c             1         1         1       29m
kubecost         replicaset.apps/kubecost-cloud-cost-d65d8dbdf              0         0         0       92m
kubecost         replicaset.apps/kubecost-cluster-controller-67d98848d6     1         1         1       92m
kubecost         replicaset.apps/kubecost-finopsagent-5bc444c67b            1         1         1       79m
kubecost         replicaset.apps/kubecost-finopsagent-6c6d85d79c            0         0         0       92m
kubecost         replicaset.apps/kubecost-forecasting-64f5494c4f            1         1         1       29m
kubecost         replicaset.apps/kubecost-forecasting-7fdb7b4cf6            0         0         0       92m
kubecost         replicaset.apps/kubecost-frontend-7bc698865b               1         1         1       92m
kubecost         replicaset.apps/kubecost-local-store-59bbfbf855            1         1         1       92m
kubecost         replicaset.apps/kubecost-mcp-5d4b95887f                    1         1         1       92m

NAMESPACE   NAME                                   READY   AGE
kubecost    statefulset.apps/kubecost-aggregator   1/1     92m
