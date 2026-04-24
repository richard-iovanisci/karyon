#!/usr/bin/env bats
# tests/bats/cuda-image-03-containerd.bats
# L2 image-smoke: docker run the built image and assert config.toml.tmpl carries default_runtime_name = "nvidia" (IMG-03 / D-05).
# Wave 0 stub — body filled by Plan 02-02 (or 02-03 for the manifest tests).

load 'test_helper'

setup() {
  require_live
  TAG="$(cuda_image_tag)"
}

teardown() {
  :
}

@test "IMG-03: images/config.toml.tmpl baked at /var/lib/rancher/k3s/agent/etc/containerd/ sets default_runtime_name = \"nvidia\"" {
  run docker run --rm --entrypoint cat "$TAG" /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl
  [ "$status" -eq 0 ]
  [[ "$output" =~ default_runtime_name\ =\ \"nvidia\" ]]
}
