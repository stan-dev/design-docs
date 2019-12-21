#include <stan/math.hpp>

#include <boost/iterator/counting_iterator.hpp>
#include <stan/math/prim/scal/functor/parallel_reduce_sum.hpp>
#include <stan/math/rev/scal/functor/parallel_reduce_sum.hpp>
#include <stan/math/prim/scal/functor/parallel_for_each.hpp>
#include <stan/math/rev/scal/functor/parallel_for_each.hpp>

namespace poisson_hierarchical_scale_model_namespace {

// user provided Stan function
template <typename T3__>
typename boost::math::tools::promote_args<T3__>::type
hierarchical_reduce(const int& start,
                        const int& end,
                        const std::vector<int>& y,
                        const Eigen::Matrix<T3__, Eigen::Dynamic, 1>& log_lambda_group,
                    const std::vector<int>& gidx, std::ostream* pstream__);

template <typename T3>
inline typename boost::math::tools::promote_args<T3>::type
parallel_hierarchical_reduce(const std::vector<int>& y,
                             const Eigen::Matrix<T3, Eigen::Dynamic, 1>& log_lambda_group,
                             const std::vector<int>& gidx,
                             const int& grainsize,
                             std::ostream* pstream__) {
  typedef boost::counting_iterator<int> count_iter;
  typedef typename boost::math::tools::promote_args<T3>::type return_t;
  const int elems = y.size();

  typedef typename boost::math::tools::promote_args<T3>::type local_scalar_t__;
  typedef local_scalar_t__ fun_return_scalar_t__;

  // C++ only binds with a lambda the arguments of the user function
  return_t lpmf = stan::math::parallel_reduce_sum(
      count_iter(1), count_iter(elems+1), return_t(0.0),
        [&](int start, int end) {
          return hierarchical_reduce(start, end, y, log_lambda_group, gidx, pstream__);
        }, grainsize);

  return lpmf;
}

// defined by user in Stan program
template <typename T1__>
typename boost::math::tools::promote_args<T1__>::type
hierarchical_map(const int& g,
                     const Eigen::Matrix<T1__, Eigen::Dynamic, 1>& log_lambda,
                 const std::vector<std::vector<int> >& yg, std::ostream* pstream__);

template <typename T1__>
std::vector<typename boost::math::tools::promote_args<T1__>::type>
parallel_hierarchical_map(const std::vector<int>& group,
                          const Eigen::Matrix<T1__, Eigen::Dynamic, 1>& log_lambda,
                          const std::vector<std::vector<int> >& yg, std::ostream* pstream__) {
  
  typedef typename boost::math::tools::promote_args<T1__>::type return_t;
  const int elems = group.size();

  // C++ only binds with a lambda the arguments of the user function
  std::vector<return_t> lpmf = stan::math::parallel_map(
      group.begin(), group.end(),
        [&](int g) -> return_t {
          return hierarchical_map(g, log_lambda, yg, pstream__);
        });
  
  return lpmf;
}

}

