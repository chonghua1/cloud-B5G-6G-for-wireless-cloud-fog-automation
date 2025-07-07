
1. 使用docker build先构建5gc和gnb镜像
2. 创建local Docker Registry：
   `docker run -d -p 5000:5000 --restart=always --name registry registry:2
`
Tag the image for the local registry
`docker tag docker-5gc:latest localhost:5000/docker-5gc:latest
`
Push the image to the local registry
`docker push localhost:5000/docker-5gc:latest
`
3. 5gc 和 gnb docker compose file 转化成k3s的deployment file:

创建 name space:
```yml
apiVersion: v1
kind: Namespace
metadata:
  name: ran
```
创建 subnet:
```yml
apiVersion: kubeovn.io/v1
kind: Subnet
metadata:
  name: ran-subnet
  namespace: ran
spec:
  protocol: IPv4
  cidrBlock: 10.53.1.0/24
  gateway: 10.53.1.1
  gatewayType: distributed
  excludeIps: ["10.53.1.1"]
  natOutgoing: false
  private: false
```

5gc config file:
```yml
apiVersion: v1
kind: ConfigMap
metadata:
  name: open5gs-env
  namespace: ran
data:
  MONGODB_IP: "127.0.0.1"
  OPEN5GS_IP: "10.53.1.2"
  UE_IP_BASE: "10.45.0"
  UPF_ADVERTISE_IP: "10.53.1.2"
  DEBUG: "false"
  SUBSCRIBER_DB: "subscriber_db.csv"
```


5gc deployment file:
```yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: open5gs-5gc
  namespace: ran
  labels:
    app: open5gs-5gc
spec:
  replicas: 1
  selector:
    matchLabels:
      app: open5gs-5gc
  template:
    metadata:
      labels:
        app: open5gs-5gc
      annotations:
        ovn.kubernetes.io/ip_address: "10.53.1.2"
        ovn.kubernetes.io/logical_switch: "ran-subnet"
    spec:
      nodeName: yijia-thinkbook-14-g6-irl
      containers:
      - name: open5gs-5gc
        image: localhost:5000/docker-5gc:latest
        ports:
        - containerPort: 9999
          protocol: TCP
        envFrom:
        - configMapRef:
            name: open5gs-env
        securityContext:
          privileged: true
        command: ["/bin/sh", "-c", "./open5gs_entrypoint.sh 5gc -c /open5gs/open5gs-5gc.yml"]
        readinessProbe:
          exec:
            command: ["/bin/sh", "-c", "nc -z 127.0.0.20 7777"]
          initialDelaySeconds: 3
          periodSeconds: 3
          timeoutSeconds: 1
          successThreshold: 1
          failureThreshold: 60
        volumeMounts:
        - name: config-volume
          mountPath: /path/to/open5gs-5gc.yml
      volumes:
      - name: config-volume
        configMap:
          name: open5gs-env
```

gNB deployment file:
```yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: srsran-gnb
  namespace: ran
  labels:
    app: srsran-gnb
spec:
  replicas: 1
  selector:
    matchLabels:
      app: srsran-gnb
  template:
    metadata:
      labels:
        app: srsran-gnb
      annotations:
        ovn.kubernetes.io/ip_address: "10.53.1.3"
        ovn.kubernetes.io/logical_switch: "ran-subnet"
    spec:
      nodeName: yijia-thinkbook-14-g6-irl # Specify the node if needed
      containers:
        - name: srsran-gnb
          image: localhost:5000/docker-gnb
          securityContext:
            privileged: true
            capabilities:
              add:
                - SYS_NICE
                - CAP_SYS_PTRACE
          volumeMounts:
            - name: usb-devices
              mountPath: /dev/bus/usb
            - name: uhd-images
              mountPath: /usr/share/uhd/images
            - name: gnb-storage
              mountPath: /tmp
            - name: gnb-config
              mountPath: /config.yml
              subPath: gnb_config.yml
          command: [ "gnb", "-c", "/config.yml", "amf", "--addr", "10.53.1.2", "--bind_addr", "10.53.1.3" ]
      volumes:
        - name: usb-devices
          hostPath:
            path: /dev/bus/usb
        - name: uhd-images
          hostPath:
            path: /usr/share/uhd/images
        - name: gnb-storage
          emptyDir: {}
        - name: gnb-config
          configMap:
            name: gnb-config-map

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: gnb-config-map
  namespace: ran
data:
  gnb_config.yml: |
    amf:
      addr: 10.53.1.2
      bind_addr: 10.53.1.3
    ru_sdr:
      device_driver: uhd
      device_args: type=b200,num_recv_frames=64,num_send_frames=64
      sync:
      srate: 23.04
      otw_format: sc12
      tx_gain: 80
      rx_gain: 70
    cell_cfg:
      dl_arfcn: 627340
      band: 78
      channel_bandwidth_MHz: 20
      common_scs: 30
      plmn: "00101"
      tac: 7
      pci: 1
    cu_cp:
      inactivity_timer: 7200
    log:
      filename: /tmp/gnb.log
      all_level: info
      hex_max_size: 0
    pcap:
      mac_enable: false
      mac_filename: /tmp/gnb_mac.pcap
      ngap_enable: false
      ngap_filename: /tmp/gnb_ngap.pcap
      e2ap_enable: true
      e2ap_filename: /tmp/gnb_e2ap.pcap
```

 
4. 首先在host上新建一个veth pair: 
`sudo ip link add veth-host type veth peer name veth-ns `
1. 为veth pair在host这一端的interface分配ip:
`sudo ip addr add 10.50.1.1/24 dev veth-host `
`sudo ip link set veth-host up `
1. 在host部署k3s server，注意server ip是veth-host的ip:
`curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --node-ip 10.50.1.1 --node-external-ip 10.50.1.1" sh -s - --flannel-backend none --disable-network-policy  --token 12345
`
1. 安装kube-ovn:
[kube-ovn installtion](https://kubeovn.github.io/docs/stable/en/start/one-step-install/#script-installation)
1. 在k3s server创建一个namespace ran
2. 创建一个subnet用于5gc和gNB通信的子网，需要指定CIDR
3. 部署5gc pod，gNB pod 
4. 在5gc pod内部设置veth-pair的另一端：
   host执行： (注意使用 `ip netns list` 查询对应的5gc pod对应的namespace名称)
   `sudo ip link set veth-ns netns cni-d7a8aa7d-ca6b-260a-103c-eb84263fc59b `
   `sudo ip netns exec cni-d7a8aa7d-ca6b-260a-103c-eb84263fc59b ip addr add 10.50.1.2/24 dev veth-ns `
   `sudo ip netns exec cni-d7a8aa7d-ca6b-260a-103c-eb84263fc59b ip link set veth-ns up `
5. 开启UE，连接到5gc
6. 路由配置：
在host执行
`sudo ip route add 10.45.1.6/32 via 10.50.1.2 dev veth-host `
`sudo iptables -A FORWARD -i veth-host -o wlp0s20f3 -j ACCEPT `
`sudo sysctl -w net.ipv4.ip_forward=1 `
`sudo iptables -t nat -A POSTROUTING -o wlp0s20f3 -j MASQUERADE`
`sudo iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o wlp0s20f3 -j MASQUERADE `
在5gc pod内部执行
`echo 1 > /proc/sys/net/ipv4/ip_forward `
`iptables -t nat -A POSTROUTING -o ogstun -j MASQUERADE `
`iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE `

1. 此时UE和k3s server node 之间应该可以互相 ping 通,并且server node上部署的pod 和 UE 之间也可以互相 ping 通

2.  部署k3s agent 节点到UE：
[k3s agent installtion](https://docs.k3s.io/quick-start#install-script)