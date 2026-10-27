Censoring and truncation
=========================

A lifetime model describes the duration until a single event of interest occurs. That event
is often a failure, which is why failures are used as the running example on this page (the
example datasets record failures), but everything below applies to any unique event you choose.

Lifetime data is rarely a clean list of "the event occurred after :math:`t` units of time".
Event might not have occured when the study ends, monitoring starts after some assets
have already been in service for a while, and dates are sometimes only approximately known.
Any of these turns a simple "event at time :math:`t`" record into something less direct, and
ignoring that distinction leads to systematically wrong estimates. AssetLife handles it
through three arguments, ``time``, ``event`` and ``entry`` which are described below.

The observation scheme
-------------------------

For each asset, four dates matter: when the *observation window* starts (:math:`t_{start}`)
and ends (:math:`t_{end}`), when the asset's lifetime starts (:math:`t_{init}`, typically its
installation), and when the event occurred (if that was actually observed). In the figure
below, the event is a failure, dated :math:`t_{fail}`, and six assets are lined up on the same
calendar to show combinations that can occur:

.. figure:: /_static/figures/observation_scheme.png
    :alt: Observation scheme for six assets, showing complete observations, right-censoring, left-censoring, left-truncation and right-truncation.
    :width: 100%

    Observation scheme for six assets. A filled circle is an observed failure; an open circle
    means the asset was still working when the observation window ended at :math:`t_{end}`
    (**right-censoring**, assets 1 and 5); a left-pointing triangle means the asset was found
    already broken, so it did not fail during the study but the exact date was never recorded 
    (**left-censoring**, asset 2); a right-pointing triangle before :math:`t_{start}` means 
    the asset was already installed before observation began (**left-truncation**, assets 
    1, 2, 4 and 6); and the dashed line is an asset that had already failed 
    before :math:`t_{start}` (**right-truncation**, asset 6).

AssetLife's ``event``/``entry`` pair covers the two cases that dominate industrial asset data
(right-censoring and left-truncation), which is why they are the two arguments widely used in
AssetLife's functions. The rarer cases, left-censoring (asset 2 above) and interval-censoring,
are expressed by giving ``time`` as intervals instead of durations, see `Left censoring`_ and
`Interval censoring`_. Right-truncated assets are left out of the study altogether, see
`Right truncation`_.

Right censoring
----------------

An observation is **right-censored** when the actual event time is unknown: the event had
not occurred yet the last time the asset was observed, so all we know is that its lifetime is
*at least* ``time``. This is flagged with ``event=False``, while ``event=True`` means the
event was observed at ``time``.

The ``load_power_transformer`` dataset (see :doc:`datasets`), where the event is a failure,
has both kinds of rows:

>>> from assetlife.datasets import load_power_transformer
>>> dataset = load_power_transformer()
>>> dataset[dataset["event"] & (dataset["entry"] == 0)][:2]  # observed failures
array([(12.4,  True, 0.), (12.6,  True, 0.)],
      dtype=[('time', '<f8'), ('event', '?'), ('entry', '<f8')])
>>> dataset[~dataset["event"] & (dataset["entry"] == 0)][:2]  # still in service at "time"
array([(21.6, False, 0.), ( 4.2, False, 0.)],
      dtype=[('time', '<f8'), ('event', '?'), ('entry', '<f8')])

Out of the 1650 transformers in the dataset, only a small fraction were actually observed
failing:

>>> dataset["event"].sum(), len(dataset)
(np.int64(318), 1650)

Left truncation
-----------------

An observation is **left-truncated** when the asset had already reached some age without the
event occurring before it was observed. For instance, monitoring only started once a
transformer had already been in service for a while. Assets of the same population whose event
occurred *before* observation are invisible to the dataset, which biases naive estimates
towards longer lifetimes if left unaccounted for. This is captured with the ``entry`` field:
the age at which the asset entered observation (``entry=0`` if it was observed from the start
of its lifetime).

>>> dataset[dataset["event"] & (dataset["entry"] > 0)][:2]
array([(34.3,  True, 34.), (45.1,  True, 44.)],
      dtype=[('time', '<f8'), ('event', '?'), ('entry', '<f8')])

Here, both transformers were already 34 and 44 (respectively) units old when they were
first observed, and were then failing shortly after, at 34.3 and 45.1. More than 70% of
the fleet in this dataset was already in service before observation:

>>> (dataset["entry"] > 0).sum(), len(dataset)
(np.int64(1158), 1650)

Left censoring
----------------

An observation is **left-censored** when the event did occur while the asset was part of the
study, but its exact date is unknown: for a failure, the asset was found already broken, so
all that is known is that its lifetime is *at most* the age at which that was noticed. It is
the mirror image of right censoring, and the opposite of it in terms of what is missing:
there the event had not happened yet, here it happened without being dated.

``event`` cannot express this, since it only distinguishes "event at ``time``" from "no event
yet at ``time``". A left-censored observation is written as an interval whose lower bound is
the start of the asset's lifetime, ``[0., b]``, see `Interval censoring`_.

Interval censoring
--------------------

An observation is **interval-censored** when the event date is known to fall between two
dates and no better than that, typically between two periodic inspections. Left censoring is
the special case where the lower bound is the start of the asset's lifetime. Both are passed
by giving ``time`` as a **two-column array** of interval bounds instead of a one-dimensional
array of durations. Each row is then read as :math:`[a_i, b_i]`, the event being somewhere
in between:

.. list-table::
    :header-rows: 1
    :widths: 30 70

    * - Row
      - Meaning
    * - ``[t, t]``
      - event observed at ``t`` (complete observation)
    * - ``[a, b]``
      - event between ``a`` and ``b`` (interval censoring)
    * - ``[0., b]``
      - event before ``b``, exact date unknown (left censoring)
    * - ``[a, np.inf]``
      - no event yet at ``a`` (right censoring)

The two degenerate bounds, ``0.`` and ``np.inf``, are what make left and right censoring
special cases of the same interval form: an unknown lower bound is the start of the asset's
lifetime, an unknown upper bound is "not yet". A left-censored asset, whose event occurred
without a recorded date, is a row ``[0., b]``; a right-censored one, still without event when
last seen, is a row ``[a, np.inf]``. ``event`` is redundant with this encoding and must be
left out, while ``entry`` keeps its meaning.

Concretely, the two bounds are assembled into an ``(n, 2)`` array, one row per asset:

.. code-block:: python

    import numpy as np

    # an exact failure, then an asset found broken between two inspections,
    # then an asset found broken with no date at all, then an asset still working
    time = np.array([
        [15.0, 15.0],
        [20.0, 25.0],
        [0.0, 8.0],
        [30.0, np.inf],
    ])

Each row then contributes to the likelihood according to which of the two bounds is degenerate:
a complete observation contributes a density, an interval the probability mass it contains,
and the two censored forms reduce to :math:`F(b)` and :math:`S(a)` respectively, since
:math:`F(0) = 0` and :math:`F(\infty) = 1`. :ref:`maximum_likelihood` writes out the four
terms.

.. warning::

    The interval form is part of the data model but is not usable for fitting in the current
    release: ``fit`` rejects a two-column ``time`` before reaching the likelihood. Use the
    one-dimensional ``time`` with ``event`` and ``entry``, as in `Fitting with censoring and
    truncation`_.

Right truncation
------------------

An observation is **right-truncated** when the event occurred *before* the observation window
opened, like asset 6 in the figure above: nothing about it falls inside the window, so it
provides neither an age at which it was seen without the event nor an event date the study
can place.

There is no argument for this case because there is nothing to pass: such an asset is simply
excluded from the study. The likelihood (see :ref:`maximum_likelihood`) has terms for
complete, right-censored, interval-censored and left-truncated observations, and none for
right truncation.

The exclusion is not neutral, though, and it is the reason ``entry`` matters. The assets
dropped this way are precisely the short-lived ones, so what remains in the window is a
population that survived long enough to be seen, which is the survivor bias described in
`Why getting this right matters`_ below. Keeping such a record instead of dropping it would
mean committing to what is known about it, namely that the event happened somewhere between
the start of its lifetime and :math:`t_{start}`, which is an interval observation (see
`Interval censoring`_).

Why getting this right matters
---------------------------------

Mishandling either one doesn't just add noise: it biases the result in a predictable
direction, and the effect can be large. On a fleet of high-voltage assets, estimating
a mean lifetime under three assumptions gives:

.. figure:: /_static/figures/censoring_bias.png
    :alt: Survival curves and mean lifetimes under three assumptions about the same industrial dataset: 16, 38, and 46 years.
    :width: 100%

    Same dataset, three assumptions. Counting only
    observed failures and ignoring the still-working assets (**mortality bias**) gives a mean
    lifetime of 16 years. Accounting for right-censoring but ignoring left-truncation
    (**survivor bias**) gives 46 years. Accounting for both gives 38 years: the correct
    figure lies in between, not at either extreme.

Ignoring censoring entirely (mortality bias) systematically *underestimates* lifetimes, since
the (longer-lived) censored assets get discarded or miscounted as short-lived ones. Ignoring
left-truncation (survivor bias) does the opposite: it *overestimates* lifetimes, because assets
whose event occurred before observation are invisible to the sample, leaving only the assets
that lasted long enough to be seen. This is exactly why every AssetLife lifetime model
accounts for both directly in its likelihood (see :ref:`maximum_likelihood`), rather than
requiring you to drop or approximate either kind of observation.

Fitting with censoring and truncation
---------------------------------------

Both are passed to ``fit`` together: AssetLife builds the correct likelihood contribution for
each row depending on its ``event``/``entry`` combination:

>>> from assetlife.lifetime_models import Weibull
>>> weibull = Weibull().fit(dataset["time"], event=dataset["event"], entry=dataset["entry"])
>>> weibull.get_params()
array([3.46597396, 0.0122785 ])

Dropping ``entry`` (i.e. ignoring the left truncation) changes the fitted parameters, since
the model is then implicitly assuming every asset was observed from the start of its lifetime:

>>> weibull_no_truncation = Weibull().fit(dataset["time"], event=dataset["event"])
>>> weibull_no_truncation.get_params()
array([4.11911713, 0.0122451 ])
