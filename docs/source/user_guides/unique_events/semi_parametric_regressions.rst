.. _cox_model:

Semi-parametric regressions
==========================================

``ParametricProportionalHazard`` (see :doc:`parametric_regressions`) requires a baseline shape, 
and the coefficients absorb whatever the shape gets wrong. The Cox proportional hazard
model removes that assumption: it estimates the covariate effect while leaving the baseline
hazard entirely unspecified. Hence "semi-parametric": only the covariate part is parametric.

Fitting the Cox model
------------------------------------------

>>> import numpy as np
>>> from assetlife.datasets import load_insulator_string
>>> from assetlife.lifetime_models import SemiParametricProportionalHazard
>>> insulator_data = load_insulator_string()
>>> covar = [
...     insulator_data["pHCl"], insulator_data["pH2SO4"], insulator_data["HNO3"]
... ]
>>> cox = SemiParametricProportionalHazard(
...     time=insulator_data["time"], covar=covar, event=insulator_data["event"]
... )
>>> np.round(cox.get_params(), 3)
array([ 5.088, -2.986,  4.518])

These three coefficients are directly comparable to the first three of the
``ParametricProportionalHazard`` fit of :doc:`parametric_regressions`: same sign, same
ordering, obtained without needing to get the baseline shape right. Like every coefficient in
these pages, they are returned on the log-hazard scale, so they must be exponentiated to be
read as hazard ratios, which is how Cox regression is usually reported:

>>> np.round(np.exp(0.1 * cox.get_params()), 3)
array([1.663, 0.742, 1.571])

These hazard ratios are read exactly as in the parametric case (see :ref:`hazard_ratio`): the
baseline cancels out of the ratio, so leaving it unspecified changes nothing to their meaning.
Per 0.1 unit again, and the same story as the parametric fit: acid exposure raises the failure
rate, ``pH2SO4`` lowers it.

Because there's no parametric baseline, ``sf`` returns the estimated timeline together with
the survival values, rather than evaluating at arbitrary times like a parametric model
would:

>>> estimation = cox.sf(*(c[:2] for c in covar), se=False)
>>> timeline, sf_values = estimation.timeline, estimation.values
>>> timeline[:3]
array([1.1, 2.6, 3. ])
>>> np.round(sf_values[0][:3], 4)
array([1.    , 0.9999, 0.9999])
>>> np.round(sf_values[1][:3], 4)
array([0.9999, 0.9997, 0.9995])

.. plot::
    :context: close-figs

    >>> import matplotlib.pyplot as plt
    >>> import numpy as np
    >>> from assetlife.datasets import load_insulator_string
    >>> from assetlife.lifetime_models import SemiParametricProportionalHazard
    >>> dataset = load_insulator_string()
    >>> covar = [dataset["pHCl"], dataset["pH2SO4"], dataset["HNO3"]]
    >>> cox = SemiParametricProportionalHazard(
    ...     time=dataset["time"], covar=covar, event=dataset["event"]
    ... )
    >>> estimation = cox.sf(*(c[:2] for c in covar), se=False)
    >>> timeline, sf_values = estimation.timeline, estimation.values
    >>> _ = plt.plot(timeline, sf_values[0], label="asset 0")
    >>> _ = plt.plot(timeline, sf_values[1], label="asset 1")
    >>> _ = plt.xlabel("time")
    >>> _ = plt.ylabel("survival probability")
    >>> _ = plt.legend()
    >>> plt.show()

The two assets shown here have different covariate values (different acid exposure), hence
the different estimated survival curves.

The partial likelihood
------------------------------------------

It is called partial because it discards the information carried by *when* the failures
happened, keeping only their order. That is the price of not having to commit to a baseline
shape. Ties get Breslow's handling, and AssetLife inspects the observed tie counts to switch to
Efron's correction, which is more accurate, when failure times are heavily tied.

With :math:`t_j` the ordered distinct failure times, :math:`\mathcal{R}_j` the risk set just
prior to :math:`t_j`, :math:`\mathcal{D}_j` the units failing at :math:`t_j` and
:math:`d_j = |\mathcal{D}_j|`, AssetLife uses Breslow's handling of ties:

.. math::

    L(\beta) = \prod_j \frac{\exp \left( \beta \cdot \sum_{i \in \mathcal{D}_j} x_i \right)}
                            {\left( \sum_{i \in \mathcal{R}_j} e^{\beta \cdot x_i} \right)^{d_j}}

and switches to Efron's correction, which is more accurate, when failure times are heavily
tied (more than three failures sharing a date):

.. math::

    L(\beta) = \prod_j \frac{\exp \left( \beta \cdot \sum_{i \in \mathcal{D}_j} x_i \right)}
                            {\prod_{\alpha=0}^{d_j - 1} \left( \sum_{i \in \mathcal{R}_j} e^{\beta \cdot x_i}
                             - \frac{\alpha}{d_j} \sum_{i \in \mathcal{D}_j} e^{\beta \cdot x_i} \right)}

Censoring and truncation enter through the risk set only: unit :math:`i` belongs to
:math:`\mathcal{R}_j` when :math:`a_i < t_j \leq t_i`, that is when it had already entered
observation and had not yet left it. Interval-censored observations have no place in this
construction, since the partial likelihood is built on the *order* of the failure dates.
