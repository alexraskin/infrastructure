config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Accepted for the single Always Free edge box: no OCI agent, no in-transit
# encryption on its boot volume.
rule "oci_compute_instance_in_transit_encryption" {
  enabled = false
}

rule "oci_compute_instance_monitoring" {
  enabled = false
}

# The CNPG bucket sets versioning = "Disabled" deliberately; CNPG's own
# retentionPolicy owns backup expiry. See terraform/oracle/objectstorage.tf.
rule "oci_object_storage_bucket_versioning" {
  enabled = false
}

plugin "oci" {
  enabled = true
  version = "0.1.1"
  source  = "github.com/joelp172/tflint-ruleset-oci"

  signing_key = <<-KEY
  -----BEGIN PGP PUBLIC KEY BLOCK-----
  mDMEZ9lWDBYJKwYBBAHaRw8BAQdAzEHbV23E2TSQCqRU66OTevnXypPyk1cIdq2I
  Rx6ki8e0KEpvZWwgUGluZGVyIDxqb2VsLnBpbmRlckBwcm90b25tYWlsLmNvbT6I
  kwQTFgoAOxYhBJNOC76sc5HN/kHD+L3SQmX0bRPgBQJn2VYMAhsDBQsJCAcCAiIC
  BhUKCQgLAgQWAgMBAh4HAheAAAoJEL3SQmX0bRPgTFsBAO8hGsLsrK4rLDlCnUwt
  XfimtveFJQWSMUGZhbhp6mdLAP9I7suPIjgqZ11SMOYgLqbnJh4v1ljyUXMOkq7B
  hWDIArg4BGfZVgwSCisGAQQBl1UBBQEBB0BkwQ92oLAIXM//1zF+/vaRKPC6ZZBI
  7o7WAIcqN1iyLwMBCAeIeAQYFgoAIBYhBJNOC76sc5HN/kHD+L3SQmX0bRPgBQJn
  2VYMAhsMAAoJEL3SQmX0bRPg0eoBANoOcO6cggFrsR/dmBHvKl87R9FeMoUybn95
  9U3mQXOmAQCRsREiV4yzLsR2oCTQJyJ5d/hRsya5mKB77yJt3bk8AA==
  =PqA9
  -----END PGP PUBLIC KEY BLOCK-----
  KEY
}

plugin "cloudflare" {
  enabled = true
  version = "0.1.0"
  source  = "github.com/alexraskin/tflint-ruleset-cloudflare"

  signing_key = <<-KEY
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGp8qVwBEACkDYThrUeGtuTsqdQLvmLJqkb+jLUSdZ3s4Uw+hFuzQP4ORFI1
BbZDw3uuRoOSSuG3JHwMuAx4zjAqmF1dAtdCHvEWY/e/TmlV5wwP9E7/XAk9+Z+g
0UE8J2fKKciLVympWnxS3W2YZAfcBKPg6oVOdMSWm8NK1dSemJeTaMM14F7Kogv7
iZgYkEszow5HjSGuQRN96ZiO0lifwsTA0NseAUd3eVNqI62q+Sx9Qmy+VxojLuP2
k+cHzYfA6P+PtSTWpiQqXaGDH4ySuUVDegIjjqCyXcfpGaEczdL+w9r1Cw+uSuFb
CmEiyboMbLclW8d+NN3kUhLnqlO+4jbHz6rSittZYlqvcYFwFIbU/Zg2Q+VRYB4U
yjl2KIQwPOvRe9hH6l/SWaxa2IEF6SBPl780pRNqX38j9dMbcaq361AbMBi4ZknF
nKyFAYZt007CM6GFhUTBrr78konR5tyYT/5uPvkJTet/NcdQJ0b3Xy5XHTIbhbg2
CrMh3as3v+Z/CzQBsFfTb20OPH8x7cB0WbSNfBISc/NDQAOHhO01rqEgzpnC4Qld
k2yDYK0Aqr50/p2ifpZIqToLLUQ0xiJZWCBdSrW76Qq8z3HlPw8MzRseEBNAdA77
A0VVEb0KhIN/VhOzGQ1wzsPYbmQwFfwD/pRc+pVYoQPvTQ5tfPQw+j5rpQARAQAB
tElBbGV4IFJhc2tpbiAodGZsaW50LXJ1bGVzZXQtY2xvdWRmbGFyZSByZWxlYXNl
KSA8YWxleHJhc2tpbkBmYXN0bWFpbC5jb20+iQJUBBMBCgA+FiEEgn7D/5mPIGqe
qMhoD5xXzU7xwv0FAmp8qVwCGwMFCQPCZwAFCwkIBwIGFQoJCAsCBBYCAwECHgEC
F4AACgkQD5xXzU7xwv3Ypw//a8Z8CBinxdxhVzY7bs3t5v83sioA5uFWiPsk2SBd
xi1VLJLCMkS3QelFigsuB0dH5CwxlDggkWCMaqIe7XksEmRqLNS3eM95NwGBeU1v
gCRyKHXdxDWSNMjw2gbRjUuI42oQmczTYo0e21474ogbS1RUYMSwzB7NU24ul6jT
BusVySrkaXWuS/8JK9Jn17vmwutgqNduvipdkcS01aqsPDL2+cVaz3iJBN1I4b0i
67BTnfrBy9Ta8VqEMg3TwsMX+umcWWaagPkJTiHNZIl5mjUSzCldRR6yGX5lyWmc
UatBH6W8vzXraMwjNn2OR8GqMDeMOy9uug4S7s3NqWE/OVUt4W3Sh7exUv9RK9dg
ZxleAKf9IPnD9jWgSOIQmi7qIyXazzF1zRP1LJvW5GjUv8McJZO+hN4zUbyyV8Dt
O+6WcoBZj5+RVw09BpsjufxyP5WadzXpkxHa98vFEDTlBPJN/fBhl5dOSEuYy869
RIujyE/u3T7wetxVimk3kY8qMdN7cfuRgMIrYrju0R6oa4Fk4NqurFeca9mOw6pZ
OU6IhzlVQaIgfHckISHKV7aCUkRqJLx8XqABTAVbDB5lu19JdOf/AZIF6Pk1wGQf
PERlR28KB74aIJNifhXmdSxz8Z3z198i+Mo9sU68zg35X6mkcaEGI/Wnq8Hj4sB8
Eho=
=sfJU
-----END PGP PUBLIC KEY BLOCK-----
KEY
}