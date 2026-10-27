Parametric regressions
=============================================

A distribution alone can't account for the fact that different assets operate under
different conditions. Regressions extend a baseline distribution with covariates: for
instance, an insulator string's lifetime plausibly depends on the acid concentrations it's
exposed to (see :doc:`datasets`).

Two parametric models
------------------------------------------

AssetLife offers two parametric ways of letting a covariate vector :math:`x` act on a baseline
cumulative hazard :math:`H_0`. Proportional hazard scales the hazard,

.. math::

    H(t, x) = e^{\beta \cdot x} \, H_0(t)

while accelerated failure time rescales the timeline, so that a covariate makes the asset age
faster or slower:

.. math::

    H(t, x) = H_0 \left( t \, e^{-\beta \cdot x} \right)

In both cases :math:`\beta` is the vector of covariate coefficients, and both are fitted the
same way, with the covariates passed alongside the lifetimes:

>>> import numpy as np
>>> from assetlife.datasets import load_insulator_string
>>> from assetlife.lifetime_models import (
...     ParametricAcceleratedFailureTime, ParametricProportionalHazard, Gompertz
... )
>>> insulator_data = load_insulator_string()
>>> covar = [
...     insulator_data["pHCl"], insulator_data["pH2SO4"], insulator_data["HNO3"]
... ]
>>> regression = ParametricProportionalHazard(Gompertz()).fit(
...     insulator_data["time"], covar,
...     event=insulator_data["event"], entry=insulator_data["entry"],
... )
>>> regression.get_params()  # doctest: +SKIP
array([ 4.11133664, -2.67876549,  3.24289683,  0.22422175,  0.02944488])
>>> aft = ParametricAcceleratedFailureTime(Gompertz()).fit(
...     insulator_data["time"], covar,
...     event=insulator_data["event"], entry=insulator_data["entry"],
... )
>>> np.round(aft.get_params(), 4)  # doctest: +SKIP
array([0.1584, 0.5594, 0.0887, 0.098 , 0.0495])

In both fits the first three parameters are the covariate coefficients (for ``pHCl``,
``pH2SO4`` and ``HNO3`` respectively), and the last two are the baseline Gompertz
distribution's own parameters. Under the proportional hazard form, a positive coefficient
raises the hazard: here ``pHCl`` and ``HNO3`` shorten lifetimes while ``pH2SO4`` lengthens
them. The coefficients of the two forms are not directly comparable, since they act on
different scales, the hazard level for one and the time axis for the other.

.. _hazard_ratio:

The hazard ratio
------------------------------------------

Coefficients on the hazard scale are hard to read directly. Under the proportional hazard
form, what is interpretable is the ratio of the hazard rates of two assets, because the
baseline cancels:

.. math::

    \textrm{HR} = \frac{h(t, x_1)}{h(t, x_2)}
                = \frac{e^{\beta \cdot x_1} \, h_0(t)}{e^{\beta \cdot x_2} \, h_0(t)}
                = e^{\beta \cdot (x_1 - x_2)}

First, the ratio does not depend on :math:`t`: that is exactly what "proportional hazard" means, 
and it is an assumption about the data. If a covariate's effect fades with age, this family of 
models cannot represent it.
Second, taking :math:`x_{1, k}` and :math:`x_{2, k} = x_{1, k} + 1` on covariate `k` (raised by 
one unit) leaves :

.. math::

    \textrm{HR} = e^{\beta_k \cdot (x_{1, k} - x_{2, k})}
                = e^{\beta_k \cdot (x_{1, k} - (x_{1, k} + 1))}
                = e^{\beta_k}

so :math:`e^{\beta_k}` is the multiplicative effect on the instantaneous failure rate of a
one-unit increase in the :math:`k`-th covariate, all others held fixed. Above 1 the asset
fails faster, below 1 it lasts longer, and 1 means no effect:

>>> beta = regression.get_params()[:3]
>>> np.round(np.exp(beta), 3)  # doctest: +SKIP
array([61.028,  0.069, 25.608])

Read literally, one more unit of ``pHCl`` multiplies the failure rate by 61. That number is
almost meaningless here, and it shows why a hazard ratio must always be read against the
scale of its covariate: ``pHCl`` only ranges over 0.3 to 1.5 in this dataset, so a "one-unit
increase" is larger than the whole observed spread. Rescaling to an increment that actually
occurs, here a tenth of a unit, gives ratios you can reason about:

>>> np.round(np.exp(0.1 * beta), 3)  # doctest: +SKIP
array([1.509, 0.765, 1.383])

So +0.1 of ``pHCl`` raises the instantaneous failure rate by about 51%, +0.1 of ``HNO3`` by
about 38%, while +0.1 of ``pH2SO4`` cuts it by roughly 24%.

It is good practice to standardize the covariates before fitting, so that the coefficients are
on comparable scales. With a standard scaler, :math:`e^{\beta_k}` is the hazard ratio for a one 
**standard deviation** increase of the :math:`k`-th covariate, not a one-unit increase. To get back the
ratio per original unit, compute :math:`\textrm{HR}^{1/\sigma_k} = e^{\beta_k / \sigma_k}`.

Note also that the accelerated failure time form has no constant hazard ratio at all: 
there, :math:`e^{\beta \cdot x}` stretches the time axis, so the effect of a covariate is read as 
an aging speed rather than as a rate multiplier.
