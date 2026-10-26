Parametric regressions
=============================================

A distribution alone can't account for the fact that different assets operate under
different conditions. Regressions extend a baseline distribution with covariates: for
instance, an insulator string's lifetime plausibly depends on the acid concentrations it's
exposed to (see :ref:`datasets`).

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

The hazard ratio
------------------------------------------

Coefficients on the hazard scale are hard to read directly. Under the proportional hazard
form, what is interpretable is the ratio of the hazard rates of two assets, because the
baseline cancels:

.. math::

    \textrm{HR} = \frac{h(t, x_1)}{h(t, x_2)}
                = \frac{e^{\beta \cdot x_1} \, h_0(t)}{e^{\beta \cdot x_2} \, h_0(t)}
                = e^{\beta \cdot (x_1 - x_2)}

Two things follow. First, the ratio does not depend on :math:`t`: that is exactly what
"proportional hazard" means, and it is an assumption about your data, not a property of the
world. If a covariate's effect fades with age, this family of models cannot represent it.
Second, taking :math:`x_1` and :math:`x_2` equal everywhere except on one covariate raised by
one unit leaves

.. math::

    \textrm{HR} = e^{\beta_k}

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
about 38%, while +0.1 of ``pH2SO4`` cuts it by roughly 24%. Comparing two real assets is the
same computation applied to their difference:

>>> covar_matrix = np.column_stack(covar)
>>> round(float(np.exp(beta @ (covar_matrix[0] - covar_matrix[1]))), 3)  # doctest: +SKIP
0.265

Asset 0 is exposed to less acid than asset 1 on all three covariates, and runs at about 27%
of its failure rate at every age, which is why its survival curve sits above the other one in
the Cox plot of :doc:`semi_parametric_regressions`.

A hazard ratio is not a ratio of lifetimes, and it says nothing about absolute risk: a large
ratio applied to a tiny baseline hazard is still a tiny hazard. For that you need the
baseline, which is where the two model families part ways. Note also that the accelerated
failure time form has no constant hazard ratio at all: there, :math:`e^{\beta \cdot x}`
stretches the time axis, so the effect of a covariate is read as an aging speed rather than
as a rate multiplier.

Likelihood with covariates
------------------------------------------

The likelihood is the one described in :ref:`maximum_likelihood`, with the covariate effect
substituted into :math:`f`, :math:`H` and :math:`F`. Nothing else changes: the coefficients
:math:`\beta` join the baseline parameters :math:`\theta` in the same minimization,

.. math::

    -\log L(\beta, \theta) = - \sum_{i \in \mathcal{D}} \log f(t_i, x_i; \beta, \theta)
                             + \sum_{i \in \mathcal{C}} H(t_i, x_i; \beta, \theta)
                             - \sum_{i \in \mathcal{I}} \log \left[ F(b_i, x_i; \beta, \theta) - F(a_i, x_i; \beta, \theta) \right]
                             - \sum_i H(a_i, x_i; \beta, \theta)

The important point is that the coefficients :math:`\beta` and the baseline parameters
:math:`\theta` are estimated **jointly**, in a single optimization: the covariate effect you
read off depends on the baseline shape you assumed. So the shape has to be chosen with the
same care as in the distribution-only case, and the same information criteria arbitrate,
counting all parameters, coefficients included:

>>> round(regression.fitting_results.aic, 1)  # doctest: +SKIP
np.float64(24431.4)
>>> round(aft.fitting_results.aic, 1)
np.float64(26464.8)

Both models have five parameters, so on this dataset the proportional hazard form fits
distinctly better than the accelerated failure time one.
