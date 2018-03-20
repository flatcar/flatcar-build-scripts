# Adding update to Coreroller

To add an update to Coreroller, first get into an SDK environment using [cork](https://github.com/coreos/mantle/tree/master/cmd/cork).

You need to have the user and password to our [Coreroller server][coreroller-server], the public and private update keys, and SSH access to our origin server (`origin.release.flatcar-linux.net`).

Then, run the [`add_package` script](../add_package) scripts with the right options.

Note that the update payload generator needs a pair of dummy keys to work, so make sure you have those.
The keys directory should look like this:

```
$ ls keys/
dummy.key.pem  dummy.pub.pem  flatcar.key.pem  flatcar.pub.pem
```

After the package is uploaded, you can promote it to a channel by using the [Coreroller UI][coreroller-server].

## Example

To add version 1688.2.0 (beta), you should run:

```
$ COREROLLER_USER=admin COREROLLER_PASS=**** ./add_package.sh keys/ https://public.update.flatcar-linux.net origin.release.flatcar-linux.net beta 1688.2.0
```

[coreroller-server]: https://public.update.flatcar-linux.net
