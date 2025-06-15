# Time Limit Transmission Seeding

A bash script to control how long torrents are seeded in Transmission.

This script allows you to configure seeding duration, filter torrents based on various criteria and decide what to do once the time limit is reached.

## Requirements

- `transmission-remote`
- `bash`
- `jq`

## ⚙Configuration

Edit the script to customize the following variables to suit your needs:

### Transmission Remote Setup

```
transmission-remote 127.0.0.1:9091 -n user:password
````
Configure your IP, Port and USER/PASSWORD if required.

### Torrent Filtering

```
TORRENT_FILTER="iu"
```
These filters do not need space seperating
* **i**: idle
* **u**: uploading
* **d**: downloading

Special filters (space-separated):
```
TORRENT_FILTER_SPECIAL=""
```



* `l:label` - torrent has specific **label**
* `n:str` - torrent **name** contains string
* `r:ratio` - minimum **upload ratio**

To **negate** a filter, prefix with `~`.
Example: `~l:alwaysseed` - excludes torrents labeled `alwaysseed`.

### Some confirmation checks

```
CHECK_ADDED_DATE=1
CHECK_ERRORED_TORRENTS=1
```

* `CHECK_ADDED_DATE`, uses the torrents `Added Date` (or `Done Date` if available) when `Seconds Seeding` is not reported.
* `CHECK_ERRORED_TORRENTS` Set to `0` allows skipping torrents with errors.

### Final Torrent State

```
TORRENT_FINAL_STATE="stop"
```

* Options:

  * `stop` - stops the torrent
  * `remove` - removes torrent from Transmission
  * `remove-and-delete` - removes and ⚠️**deletes the downloaded data**⚠️

```
FILE_DELETE=0
```

* Set to `1` to confirm deletion of data (only applies to `remove-and-delete`)

### Seeding Duration

```
SEED_DAYS=35
SEED_HOURS=0
```

Total seeding time = `SEED_DAYS + SEED_HOURS`

### DEBUG

```
ENABLE_DEBUG=1
LOGLINES=0
```
Enable debugging `1` to run the script with extra logging enabled, while debugging is enabled the script will not take action on any torrents.
Optionally set `LOGLINES` to 0 to remove the logger line cap. Default `1000`

---

## Usage

Run the script periodically via `cron`, a systemd timer, or manually.

---

## ⚠️ Disclaimer

Caution when using the `remove-and-delete` option. Always double-check your filters and configuration to prevent accidental data loss. Run with DEBUG enabled and check log output before using it live.
