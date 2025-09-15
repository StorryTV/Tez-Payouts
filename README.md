# Tez-Payouts
Simple script for tezos bakers to payout tezos delegators.

----------

Install requirements, download latest tez-payouts.sh script and automatically add a cronjob for the tezos user if it doesn't exist yet using the following oneliner command: 
```
sudo bash -c 'curl -fsSL https://raw.githubusercontent.com/StorryTV/Tez-Payouts/refs/heads/main/install.sh | bash -s --'
```

Check the last 100 lines of the log with the following command:
```
tail -n 100 /var/log/tez-payouts.log
```

Or get a realtime stream of the log using:
```
tail /var/log/tez-payouts.log -f
```

----------

Or just download the latest tez-payouts.sh script if you already have everything setup or know what you're doing from the following url: https://raw.githubusercontent.com/StorryTV/Tez-Payouts/refs/heads/main/tez-payouts.sh
