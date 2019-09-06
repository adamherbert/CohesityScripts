# Copyright 2019 Cohesity Inc.

import datetime
import json
import argparse

from cohesity_management_sdk.cohesity_client import CohesityClient

CLUSTER_USERNAME = 'admin'
CLUSTER_PASSWORD = 'admin'
CLUSTER_VIP = '10.99.1.57'
DOMAIN = 'LOCAL'


def main(args):
  vm_name = args.vm_name
  protected = "protected" if args.only_protected else None

  cohesity_client = CohesityClient(cluster_vip=CLUSTER_VIP,
                                   username=CLUSTER_USERNAME,
                                   password=CLUSTER_PASSWORD,
                                   domain=DOMAIN)
  ps_object_list = cohesity_client.search.search_protection_sources(
      vm_name, protected, None, None, None, None, None, 256)

  for ps_object in ps_object_list:
    if args.exact_match and (ps_object.source.name != args.vm_name):
      continue
    ps_run = cohesity_client.search.search_protection_runs(ps_object.uuid)
    ps_jobs = []
    if ps_object.jobs:
      for job in ps_object.jobs:
        ps_jobs.append(
          {'name' : job.job_name, 'status' : job.last_protection_job_run_status})
    num_snapshots = 0
    if ps_run:
      num_snapshots = ps_run.backup_runs[0].num_snapshots
    logical_size_gb = ps_object.logical_size_in_bytes / 1073741824
    print("Name: {}\nEnvironment: {}\nSize: {}\nJob: {}\nNumber of Snapshots:{}\n".format(
        ps_object.source.name,
        ps_object.source.environment,
        logical_size_gb,
        ', '.join(
            '[' + str(', '.join({job['name'], job['status']}) + ']') for job in ps_jobs),
        num_snapshots
    ))


if __name__ == '__main__':
  parser = argparse.ArgumentParser()
  parser.add_argument(
      "--vm_name", help="Name of the VM to find.", required=False)
  parser.add_argument(
      "--only_protected", action="store_true", help="Only return protected VMs", required=False)
  parser.add_argument(
      "--exact_match", action="store_true", help="Only VM with exact name match", required=False)
  args = parser.parse_args()
  main(args)
