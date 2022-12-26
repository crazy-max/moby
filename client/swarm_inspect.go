package client

import (
	"context"
	"encoding/json"

	"github.com/docker/docker/v24/api/types/swarm"
)

// SwarmInspect inspects the swarm.
func (cli *Client) SwarmInspect(ctx context.Context) (swarm.Swarm, error) {
	serverResp, err := cli.get(ctx, "/swarm", nil, nil)
	defer ensureReaderClosed(serverResp)
	if err != nil {
		return swarm.Swarm{}, err
	}

	var response swarm.Swarm
	err = json.NewDecoder(serverResp.body).Decode(&response)
	return response, err
}
