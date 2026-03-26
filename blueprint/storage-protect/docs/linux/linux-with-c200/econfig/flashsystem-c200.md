### Medium FlashSystem C200 storage configuration (econfig)

This file provides the YAML entries for the FlashSystem C200 storage in a medium blueprint.  Use these values in your response file to ensure that the blueprint script creates the proper volumes.

```yaml
storage:
  array_type: flashc200
  mdisk_groups:
    flash_grp:
      disks: 0-23              # Single DRAID6 array using all 24 FCMs
      raid: draid6
      stripe_width: 20         # Typical for 24-drive DRAID6 (24-4 parity = 20 data)
      rebuild_areas: 2

  volumes:
    db:
      group: flash_grp
      count: 8
      size_gb: 642

    actlog:
      group: flash_grp
      count: 1
      size_gb: 147

    archlog:
      group: flash_grp
      count: 1
      size_gb: 2048

    backup:
      group: flash_grp
      count: 3
      size_gb: 15360

    filepool:
      group: flash_grp
      count: 12
      size_gb: 29998
```

Adjust disk indices to match your FlashSystem C200 configuration.  The script will automatically assign device names and mount points based on these definitions.