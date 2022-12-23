export build_vars="$build_vars network name docker_opts subnet"

export network="$NAMESPACE-network-$ENV"
export name="${NAMESPACE}-${app}-${ENV}"
export subnet="$(_cfg_get networks "$ENV")"
export docker_opts="--network=$network --name $name --ip $(_cfg_get_ip $ENV $app)"
