# Creating the Musicbrainz database

## Presequisites
See https://github.com/metabrainz/musicbrainz-server/blob/master/INSTALL.md
"Prerequisites" and "Installing Perl dependencies" sections.
For creating the database only Perl and its dependencies are required.

## Installation

1. Download Musicbrainz source code
```bash
git clone --recursive git://github.com/metabrainz/musicbrainz-server.git
cd musicbrainz-server
```

2. Copy and modify the configuration file
```bash
cp lib/DBDefs.pm.sample lib/DBDefs.pm
vim lib/DBDefs.pm
# change port if using a different port
# change SYSTEM username if using a different one than "postgres"
```

3. Download the DB data https://musicbrainz.org/doc/MusicBrainz_Database/Download#Download (download latest fullexport `mbdump.tar.bz2`).

4. Create database and import dump
```bash
./admin/InitDb.pl --createdb --import mbdump.tar.bz2 --echo
```

## Generate random queries
The `generate_queries.py` script will create a folder `queries/` containing
the generated random queries:
```bash
./generate_queries.py
```