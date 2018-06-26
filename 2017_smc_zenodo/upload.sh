set -x
cd /tmp
rm -rf 2017_smc_zenodo*
git clone /media/Data1/work/2017_smc_zenodo
zip -r 2017_smc_zenodo.zip 2017_smc_zenodo
rsync -aP 2017_smc_zenodo.zip sd@create.aau.dk@people.create.aau.dk:tdir/
