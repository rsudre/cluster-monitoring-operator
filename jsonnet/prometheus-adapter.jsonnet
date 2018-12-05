local k = import 'ksonnet/ksonnet.beta.3/k.libsonnet';
local service = k.core.v1.service;
local deployment = k.apps.v1beta2.deployment;
local container = deployment.mixin.spec.template.spec.containersType;
local volume = deployment.mixin.spec.template.spec.volumesType;
local configmap = k.core.v1.configMap;
local containerPort = container.portsType;
local containerVolumeMount = container.volumeMountsType;
local tmpVolumeName = 'volume-directive-shadow';
local tlsVolumeName = 'kube-state-metrics-tls';

{
  prometheusAdapter+:: {
    local tlsVolumeName = 'prometheus-adapter-tls',
    local tlsPath = '/etc/tls/private',

    apiService+:
      {
        metadata+: {
          annotations+: {
            'service.alpha.openshift.io/inject-cabundle': 'true',
          },
        },
      },

    service+:
      {
        metadata+: {
          annotations+: {
            'service.alpha.openshift.io/serving-cert-secret-name': tlsVolumeName,
          },
        },
        spec+: {
          type: 'ClusterIP',
        },
      },

    deployment+:
      {
        spec+: {
          template+: {
            spec+: {
              local servingCertsCABundle = 'serving-certs-ca-bundle',
              local servingCertsCABundleDirectory = 'ssl/certs',
              local servingCertsCABundleFileName = 'service-ca.crt',
              local servingCertsCABundleMountPath = '/etc/%s' % servingCertsCABundleDirectory,

              containers:
                std.map(
                  function(c)
                    if c.name == 'prometheus-adapter' then
                      c
                      {
                        args+: [
                          '--prometheus-ca-file=%s/%s' % [servingCertsCABundleMountPath, servingCertsCABundleFileName],
                          '--prometheus-token-file=/var/run/secrets/kubernetes.io/serviceaccount/token',
                          '--tls-cert-file=%s/%s' % [tlsPath, 'tls.crt'],
                          '--tls-private-key-file=%s/%s' % [tlsPath, 'tls.key'],
                        ],
                        volumeMounts+: [
                          containerVolumeMount.new(servingCertsCABundle, servingCertsCABundleMountPath),
                          containerVolumeMount.new(tlsVolumeName, tlsPath),
                        ],
                      }
                    else
                      c,
                  super.containers,
                ),

              volumes+: [
                volume.withName(servingCertsCABundle) + volume.mixin.configMap.withName('serving-certs-ca-bundle'),
                volume.fromSecret(tlsVolumeName, tlsVolumeName),
              ],

              securityContext: {},
              priorityClassName: 'system-cluster-critical',
            },
          },
        },
      },

    clusterRoleBindingView:
      local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;

      clusterRoleBinding.new() +
      clusterRoleBinding.mixin.metadata.withName('prometheus-adapter-view') +
      clusterRoleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
      clusterRoleBinding.mixin.roleRef.withName('cluster-monitoring-view') +
      clusterRoleBinding.mixin.roleRef.mixinInstance({ kind: 'ClusterRole' }) +
      clusterRoleBinding.withSubjects([{
        kind: 'ServiceAccount',
        name: 'prometheus-adapter',
        namespace: $._config.namespace,
      }]),
  },
}
