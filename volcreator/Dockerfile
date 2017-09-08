FROM centos:7

COPY k8s.repo /etc/yum.repos.d/k8s.repo
RUN yum install -y \
      bash \
      kubectl \
    && yum clean all

COPY creator.sh /

ENTRYPOINT [ "/creator.sh" ]
