# Submitting Public standard containers and charts to Ironbank

**Author:** Beijie Zhang
**Date:** 2/1/2023

## Overview

The Iron Bank is the DoD repository of digitally signed, binary container images that have been hardened and accredited for DoD-wide use across classifications. All containers provide a variety of information such as their build and approval date, approval status, scan results, and more. Essentially, Iron Bank is a place where DoD programs can find and utilize utilize cutting-edge software and tools.

The following documentation will discuss process for submitting public standard containers and charts to Iron Bank for review and approval.

## Components

**Approved/Hardened Base Image** are base images that exist in Iron Bank that meet or exceed the hardening standards in this guide or have been approved based on the mitigation or justification of any issues and accepted by Iron Bank Container Approver
**hardening_manifest.yml** serves as a structured data file using yaml that requires specific information such as repository, tags, labels, all resources that need to be added to the container from any upstream source, maintainers, etc
**Justifications** is an explanation of why the vulnerability exists and if/when it can be resolved OR why it is a false positive or unable to exploited
**STDOUT** is the standard output on Linux, this is the default file descriptor that a process can write to, such as logs

## Steps for container approval

1. Visit <https://repo1.dso.mil>, register an account with "Sign in with Platform One SSO" if no access
2. Submit onboarding form regarding the container at <https://p1.dso.mil/products/iron-bank/getting-started>
3. IB team will create initial issues at the repo level, an email will be sent out once done
4. Request access on <https://repo1.dso.mil/dsop> if do not have it yet
5. A repo of the container should be created at this point, modify the `hardening_manifest.yml` file to include metadata info in components section
6. Make sure pipeline / gitlab-ci builds correctly
7. An engineer will be reviewing or leaving findings on the container
8. Respond to all comments and address them, communicate via comments or office hours

## Contacts

Iron Bank requires direct comments on any vulnerability or approval issues, which can be found at <https://vat.dso.mil/vat>

Alternatively, there are weekly office-hours hosted by IB that one can attend to get help - <https://www.zoomgov.com/meeting/register/vJIsd-2gqzgtGa0q_KrlTkVDhrC_0LmnSxc>

## Resources

Iron Bank site - <https://ironbank.dso.mil/about>

Contributor Guide - <https://repo1.dso.mil/dsop/dccscr/-/tree/master>

Onboarding Checklist - <https://repo1.dso.mil/platform-one/bullhorn-delivery-static-assets/-/raw/master/p1/docs/Iron%20Bank%20Container%20Hardening%20Checklist.pdf?inline=false>

Onboarding slides - <https://repo1.dso.mil/platform-one/bullhorn-delivery-static-assets/-/raw/master/p1/docs/Iron%20Bank%20Onboarding%20Presentation.pdf?inline=false>
